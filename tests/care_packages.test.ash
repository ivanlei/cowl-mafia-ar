// tests/care_packages.test.ash -- the three things care_relay.ash reads off a
// KoL page, and the arithmetic it does with the dates.
//
// Run from inside KoLmafia:
//   cp testdata/care/ar_care_*.html <KoLmafia root>/data/
//   call tests/care_packages.test.ash
//
// WHY THESE AND NOT THE PAGE. Every one of these parsers reads a page KoL
// serves, and every one of them has a way of being quietly wrong rather than
// broken -- a shorter list, a date off by twenty years, a conversation counted
// as a care package. The consequence of the third is sending a hundred and
// eighty people a second package, so it is pinned here rather than discovered
// there.
//
// Two of these are regression tests for bugs this code actually had, both
// found against the live clan and both of which produced a plausible answer:
//
//   the inactive rows   a single pattern with [^<]* between the name and the
//                       rank cell cannot cross the <font color=gray> KoL puts
//                       on an inactive account, and silently dropped all
//                       every one of them from the roster.
//   box=true            $strings[Outbox, Saved] is a SET, so `foreach i, box`
//                       binds the name to i and `true` to box. The mailbox was
//                       fetched as "box=true" and parsed as nothing at all,
//                       which looks exactly like "nobody has had a package".
//
// The second one lived in the fetch loop, which needs a live KoL and so cannot
// be reached from here. What IS pinned is the check that caught it --
// careLooksLikeBox() -- because that is the thing standing between a failed
// request and a send to everybody twice.

import <ar_care.ash>

int failures = 0;

void check(string what, boolean ok) {
	if (ok) {
		print("ok   " + what);
	} else {
		print("FAIL " + what, "red");
		failures = failures + 1;
	}
}

void checkInt(string what, int got, int want) {
	check(what + " (" + got + ")", got == want);
}

void checkString(string what, string got, string want) {
	check(what + " [" + got + "]", got == want);
}

string fixture(string name) {
	string text = file_to_buffer("data/" + name).to_string();
	if (text == "") {
		print("No data/" + name + " -- copy testdata/care/" + name
			+ " into KoLmafia's data folder first.", "red");
	}
	return text;
}

void main() {
	/* ---- the roster ---- */

	string roster = fixture("ar_care_roster.html");
	if (roster == "") return;

	care_member [int] members;
	careParseRoster(roster, members);

	checkInt("roster: every member found, inactive ones included", count(members), 5);

	care_member [int] byId;
	foreach i, m in members byId[m.who] = m;

	check("roster: id 101 found", byId contains 101);
	checkString("roster: 101's name", byId[101].name, "Ordinary Member");
	checkString("roster: 101's rank", byId[101].rank, "Officer");
	checkString("roster: 101's title", byId[101].title, "Nothing Unusual Here");
	check("roster: 101 is not inactive", !byId[101].inactive);

	// The regression. KoL writes <font color=gray><b> (inactive)</b></font>
	// after the name, and this member is only here at all because the parser
	// stopped trying to match the whole row with one pattern.
	check("roster: the inactive member is found", byId contains 102);
	check("roster: and is marked inactive", byId[102].inactive);
	checkString("roster: inactive member's rank is still read", byId[102].rank, "Recruit");

	// A title KoL escaped, and one that is only &nbsp;. Neither should take the
	// member with it.
	check("roster: member with an escaped < in the title", byId contains 103);
	check("roster: member with no title", byId contains 104);
	checkString("roster: the escaped title is kept as KoL wrote it",
		byId[103].title, "Girlypop &lt;3");

	/* ---- the skipped-rank list ---- */

	// Reads a preference, so it is saved and put back: these tests run against
	// a live character and must not leave its settings changed.
	string savedSkip = get_property(CARE_SKIP);

	set_property(CARE_SKIP, "");
	checkInt("skip: an empty setting skips nothing", count(careSkipRanks()), 0);

	set_property(CARE_SKIP, "Recruit, Bot");
	boolean [string] skip = careSkipRanks();
	checkInt("skip: two ranks read from a comma list", count(skip), 2);
	check("skip: a rank matches", skip contains "recruit");
	check("skip: the space after the comma is trimmed", skip contains "bot");

	set_property(CARE_SKIP, "  rECRUIT  ");
	skip = careSkipRanks();
	check("skip: case is ignored", skip contains "recruit");

	// THE TRAP. A clan can have both "Member" and "Senior Member" as separate
	// ranks, so a skip list matched as a substring would take members nobody
	// asked to exclude -- and silently, since the page would just show a
	// shorter list.
	set_property(CARE_SKIP, "Member");
	skip = careSkipRanks();
	check("skip: the named rank matches", skip contains "member");
	check("skip: a rank CONTAINING it does not",
		!(skip contains "senior member"));
	check("skip: and the roster has such a rank to be wrong about",
		byId contains 105 && byId[105].rank == "Senior Member");

	set_property(CARE_SKIP, savedSkip);
	checkString("skip: the setting was put back", get_property(CARE_SKIP), savedSkip);

	/* ---- a profile's last login ---- */

	string profile = fixture("ar_care_profile.html");
	if (profile == "") return;

	// Anchored on the label, not on position. Account Created sits immediately
	// above with identical markup, so an unanchored pattern reads 2005 and
	// every member looks like they last logged in the year they joined.
	checkString("profile: last login", careParseLastLogin(profile), "November 08, 2026");
	checkString("profile: a page without one answers empty",
		careParseLastLogin("<html>nothing here</html>"), "");

	/* ---- the date arithmetic ---- */

	// now_to_string(format), not today_to_string() through format_date_time --
	// whose argument order is not the one the method-call spelling suggests and
	// which quietly produced something careDaysSince then called unknown.
	checkInt("dates: today is 0 days ago",
		careDaysSince(now_to_string("MMMM d, yyyy")), 0);
	// Unknown is -1 and is never "active": a profile that would not parse
	// leaves a member out of the send rather than guessed into it.
	checkInt("dates: an empty string is unknown", careDaysSince(""), -1);
	checkInt("dates: a non-date is unknown", careDaysSince("sometime last year"), -1);
	checkInt("dates: a half-date is unknown", careDaysSince("November 2026"), -1);
	check("dates: a real date is a real number of days",
		careDaysSince("October 05, 2005") > 7000);

	/* ---- who has already had one ---- */

	string outbox = fixture("ar_care_outbox.html");
	if (outbox == "") return;

	// The guard first. A response that is not the box asked for must not read
	// as an empty box: careAlreadySent() turns a false here into a refusal to
	// send at all, which is the only safe direction when the question is "who
	// already has one".
	check("sent: the real page is recognised as the Outbox",
		careLooksLikeBox(outbox, "Outbox"));
	check("sent: and is not mistaken for the Saved box",
		!careLooksLikeBox(outbox, "Saved"));
	check("sent: an empty response is not a mailbox",
		!careLooksLikeBox("", "Outbox"));
	check("sent: nor is a page fetched as box=true",
		!careLooksLikeBox("<html>You don't have a mailbox called that.</html>", "true"));

	care_sent sent;
	sent.read = true;
	careParseSentBox(outbox, sent);

	// 101 marked, 105 marked twice (a gift is two rows), 106 marked with a
	// comma in the name. 103 is a conversation and 107 was received, not sent.
	checkInt("sent: how many recipients counted", count(sent.who), 3);
	check("sent: a marked plain send counts", sent.who contains 101);
	check("sent: a marked gift counts", sent.who contains 105);
	check("sent: a recipient with a comma in their name counts", sent.who contains 106);

	// THE ONE THAT MATTERS. A real Outbox is mostly conversation; counting it
	// would mark the whole clan as already served and send nothing to anybody.
	check("sent: an UNMARKED conversation does not count", !(sent.who contains 103));
	// And the other direction: a saved box holds received mail too, and a
	// friend quoting the marker back at you is not a package you sent.
	check("sent: a marked message RECEIVED does not count", !(sent.who contains 107));

	/* ---- a response that is not a profile at all ---- */

	// The same shape of guard as careLooksLikeBox above, and it earns its place
	// for the same reason: KoLmafia serializes its requests, so a relay request
	// landing while the gCLI is busy is answered with an empty page -- which
	// parses as "last login unreadable" rather than as nothing. Under the
	// week-long hold, caching that would pin "unreadable" on somebody for seven
	// days and no amount of pressing the button would shift it.
	check("profile: the real page is recognised as a profile",
		careLooksLikeProfile(profile));
	check("profile: an empty response is not a profile",
		!careLooksLikeProfile(""));
	check("profile: nor is KoL's 'no such player'",
		!careLooksLikeProfile("<html>No player by that name could be found.</html>"));
	// Deliberately NOT keyed on the field being read: a genuine profile with no
	// Last Login line has to stay a profile, or it would be thrown away as a
	// failed request and re-fetched for ever.
	check("profile: a profile with no last login is still a profile",
		careLooksLikeProfile("<td><b>Account Created:</b></td><td>May 1, 2005</td>"));

	/* ---- how long a scan is held, and how fast it runs ---- */

	string savedHold = get_property(CARE_HOLD);
	string savedBatch = get_property(CARE_BATCH);
	string savedPause = get_property(CARE_PAUSE);

	set_property(CARE_HOLD, "");
	checkInt("hold: unset falls back to a week", careHoldDays(), 7);
	set_property(CARE_HOLD, "0");
	checkInt("hold: zero is not a window", careHoldDays(), 7);
	set_property(CARE_HOLD, "3");
	checkInt("hold: a set value is used", careHoldDays(), 3);
	checkInt("hold: and in seconds", careHoldSeconds(), 3 * 24 * 60 * 60);

	// A row is fresh against that window and nothing else -- and a row nobody
	// has looked at is never fresh however new its stamp, which is what keeps
	// "not looked up yet" from reading as "looked up and unreadable".
	care_login row;
	row.looked = true;
	row.fetchedAt = 1000000;
	check("hold: a row inside the window is fresh",
		careLoginFresh(row, 1000000 + careHoldSeconds() - 10));
	check("hold: a row past the window is not",
		!careLoginFresh(row, 1000000 + careHoldSeconds() + 10));
	row.looked = false;
	check("hold: an unlooked row is never fresh, however new",
		!careLoginFresh(row, 1000000));

	set_property(CARE_BATCH, "");
	checkInt("batch: unset falls back to five", careScanBatch(), 5);
	set_property(CARE_BATCH, "0");
	checkInt("batch: zero would be a loop that fetches nothing", careScanBatch(), 5);
	set_property(CARE_BATCH, "9");
	checkInt("batch: a set value is used", careScanBatch(), 9);
	set_property(CARE_BATCH, "500");
	checkInt("batch: and is capped", careScanBatch(), CARE_BATCH_MAX);

	// THE ONE THAT BIT, caught before it shipped but only just. An unset
	// preference is "" and to_int()s to 0, and 0 is a value this setting
	// deliberately honours ("as fast as it answers") -- so without asking
	// whether it is set at all, never having set it would mean the fastest
	// possible scan, which is the opposite of what the default is for.
	set_property(CARE_PAUSE, "");
	checkInt("pause: unset falls back to a second, not to no pause",
		careScanPause(), 1000);
	set_property(CARE_PAUSE, "0");
	checkInt("pause: an explicit zero IS no pause", careScanPause(), 0);
	set_property(CARE_PAUSE, "250");
	checkInt("pause: a set value is used", careScanPause(), 250);
	set_property(CARE_PAUSE, "-5");
	checkInt("pause: a negative is a typo, not an intention", careScanPause(), 1000);

	set_property(CARE_HOLD, savedHold);
	set_property(CARE_BATCH, savedBatch);
	set_property(CARE_PAUSE, savedPause);
	checkString("hold: the setting was put back", get_property(CARE_HOLD), savedHold);
	checkString("batch: the setting was put back", get_property(CARE_BATCH), savedBatch);
	checkString("pause: the setting was put back", get_property(CARE_PAUSE), savedPause);

	/* ---- the held roster is replaced, never merged ---- */

	// THE FAILURE THIS IS FOR: a member who has left the clan has to disappear
	// from what is held. Merged instead of replaced they would stay, with the
	// rank they used to hold, in a list the page then offers to send a package
	// to -- and nothing about the page would look wrong.
	//
	// It writes the real file, so the real file is put back BYTE FOR BYTE in a
	// finally, which runs whether the checks pass, fail or abort. The cost of
	// that going wrong is one re-scan, and the alternative was leaving the one
	// property that matters here untested.
	string heldBefore = file_to_buffer("data/" + CARE_ROSTER_FILE).to_string();
	try {
		care_member [int] five = members;      // the 5-member fixture roster
		careSaveRoster(five);
		checkInt("roster held: five saved reads back as five",
			count(careHeldRoster()), 5);

		care_member [int] two;
		two[0] = members[0];
		two[1] = members[1];
		careSaveRoster(two);
		checkInt("roster held: saving two REPLACES the five, not merges",
			count(careHeldRoster()), 2);

		// And the stamp is this save's, which is what careSnapshotFresh reads.
		check("roster held: the snapshot is stamped as taken just now",
			careSnapshotAt() > 0 && (now_to_int() / 1000) - careSnapshotAt() < 60);
		check("roster held: and so reads as fresh", careSnapshotFresh());
	} finally {
		buffer putBack;
		putBack.append(heldBefore);
		putBack.buffer_to_file("data/" + CARE_ROSTER_FILE);
		// The file is back; the in-memory copy is still the two-member one
		// this test wrote, so it has to be dropped or everything below would
		// run against a roster of two.
		careRosterLoaded = false;
	}
	// check() and NOT checkString(), which prints what it compared: the held
	// roster is every clan member's name and title, and checkString put all
	// 16KB of it into the gCLI and from there into the debug log -- the file
	// KoLmafia asks you to attach to a bug report. Other people's names are
	// not this test's to publish.
	check("roster held: the real file was put back",
		file_to_buffer("data/" + CARE_ROSTER_FILE).to_string() == heldBefore);

	/* ---- the scan's queue ---- */

	// READ-ONLY, DELIBERATELY. Everything above works on a fixture or on a
	// preference it puts back; this works on whatever this character actually
	// has held, because writing the held roster from a test would throw away
	// the real one. So what is checked is the invariants, which hold whatever
	// is on disk -- including an empty disk.
	int [int] queue = careScanQueue();
	care_member [int] heldRoster = careHeldRoster();
	care_member [int] byWho;
	foreach i, m in heldRoster byWho[m.who] = m;

	boolean queueIsInRoster = true;
	boolean queueHasSelf = false;
	boolean queueHasInactive = false;
	foreach i, who in queue {
		if (!(byWho contains who)) queueIsInRoster = false;
		if (who == my_id().to_int()) queueHasSelf = true;
		if (byWho contains who && byWho[who].inactive) queueHasInactive = true;
	}

	check("queue: everyone in it is in the held roster", queueIsInRoster);
	check("queue: it never includes you", !queueHasSelf);
	// An account KoL has already marked inactive is one the roster tells us
	// about for free, so a profile request for it is pure waste.
	check("queue: nor an account KoL says is inactive", !queueHasInactive);
	check("queue: and it is no longer than the roster",
		count(queue) <= count(heldRoster));
	checkInt("queue: careScanTodo agrees with it", careScanTodo(), count(queue));

	/* ---- the queue against the hold window ---- */

	// WHAT THIS IS FOR, and it was found by planting the fault rather than by
	// reasoning: a queue built from "is there a row for this member" instead of
	// "is that row still fresh" passes every invariant above, because on a
	// freshly scanned clan every row IS fresh. It fails a week later, and it
	// fails silently -- the button would offer nothing to do while the page
	// showed logins eight days old, for ever.
	//
	// NOTHING IS WRITTEN TO DISK HERE. The caches are plain file-scope maps
	// (see ar_care.ash for why they stopped being static), so a test can stand
	// them up in memory, ask the question, and drop the flags again. That is
	// also why this does not need the file round-trip the save test above does.
	int nowSeconds = now_to_int() / 1000;

	// A ROW AT A TIME, with no `care_saved b = a` between them. An ASH record
	// is an aggregate and an aggregate is assigned BY REFERENCE, so copying
	// one and editing the copy edits the original: the first version of this
	// built three rows that were all the same record, the roster came out as
	// the same member three times, and two checks failed in a way that looked
	// like the queue was broken rather than the test.
	care_saved [int] standIn;
	standIn[0].who = 901;
	standIn[0].name = "Fresh Row";
	standIn[0].rank = "Member";
	standIn[0].savedAt = nowSeconds;
	standIn[0].format = CARE_ROSTER_FORMAT;

	standIn[1].who = 902;
	standIn[1].name = "Stale Row";
	standIn[1].rank = "Member";
	standIn[1].savedAt = nowSeconds;
	standIn[1].format = CARE_ROSTER_FORMAT;

	standIn[2].who = 903;
	standIn[2].name = "Already Had One";
	standIn[2].rank = "Member";
	standIn[2].savedAt = nowSeconds;
	standIn[2].format = CARE_ROSTER_FORMAT;

	care_login [int] standInLogins;
	standInLogins[901].looked = true;
	standInLogins[901].lastLogin = "November 20, 2026";
	standInLogins[901].days = 1;
	standInLogins[901].fetchedAt = nowSeconds;
	standInLogins[901].format = CARE_LOGIN_FORMAT;

	// The same row, a minute past the window.
	standInLogins[902].looked = true;
	standInLogins[902].lastLogin = "November 20, 2026";
	standInLogins[902].days = 1;
	standInLogins[902].fetchedAt = nowSeconds - careHoldSeconds() - 60;
	standInLogins[902].format = CARE_LOGIN_FORMAT;

	standInLogins[903].looked = true;
	standInLogins[903].lastLogin = "November 20, 2026";
	standInLogins[903].days = 1;
	standInLogins[903].fetchedAt = nowSeconds;
	standInLogins[903].format = CARE_LOGIN_FORMAT;

	int [int] standInSent;
	standInSent[903] = nowSeconds;

	try {
		careRosterCache = standIn;
		careRosterLoaded = true;
		careLoginCache = standInLogins;
		careLoginsRead = true;
		careSentScratch = standInSent;
		careSentScratchLoaded = true;

		int [int] standInQueue = careScanQueue();
		boolean [int] queued;
		foreach i, who in standInQueue queued[who] = true;

		checkInt("window: only the member whose row has aged out is queued",
			count(standInQueue), 1);
		check("window: the expired row is the one queued", queued contains 902);
		check("window: a row still inside the window is left alone",
			!(queued contains 901));
		check("window: and somebody the scan noted as already sent to is skipped",
			!(queued contains 903));
	} finally {
		// Drop the stand-ins so anything after this reads the real files again.
		careRosterLoaded = false;
		careLoginsRead = false;
		careLoginsDirty = false;
		careSentScratchLoaded = false;
	}

	/* ---- writing somebody else's words into a page ---- */

	// None of this was escaped until 2026-11-21. A clan rank is typed by
	// whoever runs the clan and the note is now a text box on the page, so
	// three of the strings this page draws come from outside it.
	checkString("escape: an ampersand", careHtml("Skills & Crap"), "Skills &amp; Crap");
	checkString("escape: a tag", careHtml("<b>x</b>"), "&lt;b&gt;x&lt;/b&gt;");
	checkString("escape: a double quote", careHtml("say \"hi\""), "say &quot;hi&quot;");

	// THE ONE entity_encode LEAVES ALONE, checked here because it is the
	// whole reason careAttr exists. CharacterEntities' table runs &quot;
	// &amp; &lt; &gt; and no &apos;.
	checkString("escape: an apostrophe is left alone", careHtml("it's"), "it's");

	// So an attribute value has to be DOUBLE quoted, and careAttr supplies the
	// quotes rather than trusting the caller to type the right ones. The fault
	// this is here to catch is single quotes: value='it's a gift' ends the
	// attribute at the apostrophe and renders the rest of the tag as text --
	// which works perfectly until somebody writes a note with an apostrophe in
	// it, and this page's default note has one.
	checkString("attr: double quoted, so an apostrophe inside is safe",
		careAttr("it's"), "\"it's\"");
	checkString("attr: and a double quote inside is encoded",
		careAttr("say \"hi\""), "\"say &quot;hi&quot;\"");
	check("attr: the default note survives a round trip",
		careAttr(CARE_NOTE_DEFAULT) == "\"" + CARE_NOTE_DEFAULT + "\"");

	/* ---- the three places, and the one that is not a place ---- */

	checkInt("places: three, not the anti-raffle's four",
		count(careAllSources()), 3);
	check("places: storage is not one of them", !careIsSource("storage"));
	check("places: inventory is", careIsSource("inventory"));

	// A place added without being named would get a checkbox labelled with
	// its internal key.
	foreach i, place in careAllSources() {
		check("places: " + place + " has a name of its own",
			careSourceName(place) != place && careSourceName(place) != "");
	}
	checkString("places: an unknown one is its own name",
		careSourceName("attic"), "attic");

	string savedSources = get_property(CARE_SOURCES);

	set_property(CARE_SOURCES, "");
	checkInt("places: unset means all three", count(careSources()), 3);

	// THE MIGRATION CASE. Storage was a source until 2026-11-21, so a
	// preference saved before then names four. It has to read as the three it
	// still has rather than refuse, since a page cannot show a checkbox for a
	// place that no longer exists and refusing would strand whoever has one.
	set_property(CARE_SOURCES, "inventory,closet,display,storage");
	boolean [string] places = careSources();
	checkInt("places: a saved value naming storage reads as three",
		count(places), 3);
	check("places: and storage is not among them", !(places contains "storage"));

	set_property(CARE_SOURCES, savedSources);
	checkString("places: the setting was put back",
		get_property(CARE_SOURCES), savedSources);

	/* ---- what the Config box may write ---- */

	boolean [string] settable = careSettable();
	checkInt("settable: three settings and no more", count(settable), 3);
	check("settable: the days", settable contains CARE_DAYS);
	check("settable: the places", settable contains CARE_SOURCES);
	check("settable: the note", settable contains CARE_NOTE);
	// Read-only on the page by COwliCK's decision, 2026-11-21: an item list
	// wants parsing against real item names and that is its own job.
	check("settable: and NOT the package", !(settable contains CARE_PACKAGE));
	check("settable: nor the skipped ranks", !(settable contains CARE_SKIP));

	checkString("days: a number is fine", careBadValue(CARE_DAYS, "14"), "");
	check("days: zero is not", careBadValue(CARE_DAYS, "0") != "");
	check("days: a negative number is not", careBadValue(CARE_DAYS, "-3") != "");
	check("days: a word is not", careBadValue(CARE_DAYS, "soon") != "");
	check("days: nothing at all is not", careBadValue(CARE_DAYS, "") != "");

	checkString("write places: the three together are fine",
		careBadValue(CARE_SOURCES, "inventory,closet,display"), "");
	checkString("write places: one of them is fine",
		careBadValue(CARE_SOURCES, "closet"), "");
	check("write places: none at all is refused",
		careBadValue(CARE_SOURCES, "") != "");
	check("write places: an unknown one is refused",
		careBadValue(CARE_SOURCES, "attic") != "");

	// REFUSED BY NAME, not as an unknown. Storage is the one wrong answer
	// somebody has a reason to try -- it was a source here until 2026-11-21
	// and still is one for the anti-raffle -- so "not a place this knows"
	// would read as a bug rather than as a decision.
	check("write places: storage is refused",
		careBadValue(CARE_SOURCES, "storage") != "");
	check("write places: storage beside a real one is still refused",
		careBadValue(CARE_SOURCES, "inventory,storage") != "");
	check("write places: and refused in its own words",
		careBadValue(CARE_SOURCES, "storage") != careBadValue(CARE_SOURCES, "attic"));

	checkString("note: ordinary text is fine",
		careBadValue(CARE_NOTE, "Have a good run!"), "");
	// Empty is ALLOWED and means the default sentence back, which is how
	// careNote() already reads an unset preference. Clearing the box is how
	// you get the default, rather than being told to type something.
	checkString("note: empty is allowed", careBadValue(CARE_NOTE, ""), "");

	buffer tooLong;
	while (tooLong.length() <= CARE_NOTE_MAX) tooLong.append("abcdefghij");
	check("note: one past the cap is refused",
		careBadValue(CARE_NOTE, tooLong.to_string()) != "");

	check("write: a setting the box does not carry is refused by the rule too",
		careBadValue("arTicketItems", "anything") != "");

	/* ---- who may be ticked, and who starts ticked ---- */

	// The Send column replaced eight verdict headings with one tick per row
	// (COwliCK, 2026-11-21), so these two predicates are the whole of what
	// that column means.
	check("tick: the eligible are tickable", careTickable(CARE_WOULD));
	check("tick: and start ticked", careTickedByDefault(CARE_WOULD));

	// YOURS TO OVERRULE: every one of these four is this page's own opinion or
	// a gap in what it knows, and you may know better.
	check("tick: not logged in lately is yours to tick", careTickable(CARE_QUIET));
	check("tick: a skipped rank is yours to tick", careTickable(CARE_SKIPPED));
	check("tick: an unreadable profile is yours to tick", careTickable(CARE_UNKNOWN));
	check("tick: one not looked up yet is yours to tick", careTickable(CARE_PENDING));
	check("tick: none of the four starts ticked",
		!careTickedByDefault(CARE_QUIET) && !careTickedByDefault(CARE_SKIPPED)
		&& !careTickedByDefault(CARE_UNKNOWN) && !careTickedByDefault(CARE_PENDING));

	// NOT OPINIONS, so no box is drawn at all. Ticking "already had one" is a
	// second package to somebody who has had theirs, which is the exact
	// mistake this whole page exists to prevent.
	check("tick: already had one is locked off", !careTickable(CARE_HAD));
	check("tick: an inactive account is locked off", !careTickable(CARE_INACTIVE));
	check("tick: and you are locked off", !careTickable(CARE_SELF));
	check("tick: nothing locked starts ticked",
		!careTickedByDefault(CARE_HAD) && !careTickedByDefault(CARE_INACTIVE)
		&& !careTickedByDefault(CARE_SELF));

	/* ---- every verdict has a word for itself ---- */

	// With the headings gone these eight words are the only thing saying why a
	// row has no tick, so a verdict nobody gave a word to would print its own
	// bare key into the Send column.
	string [int] everyVerdict;
	everyVerdict[0] = CARE_WOULD;
	everyVerdict[1] = CARE_HAD;
	everyVerdict[2] = CARE_QUIET;
	everyVerdict[3] = CARE_INACTIVE;
	everyVerdict[4] = CARE_SKIPPED;
	everyVerdict[5] = CARE_PENDING;
	everyVerdict[6] = CARE_UNKNOWN;
	everyVerdict[7] = CARE_SELF;
	foreach i, verdict in everyVerdict {
		check("verdict: " + verdict + " has a word that is not its key",
			careVerdictLabel(verdict) != verdict && careVerdictLabel(verdict) != "");
	}

	/* ---- the package's own problems ---- */

	// With nothing configured the page must refuse, and it must be a fatal
	// refusal -- that is what removes the send button rather than warning
	// beside it.
	care_problem [int] problems = carePackageProblems();
	if (carePackage() == "" && careMeat() <= 0) {
		check("package: an unset package is a problem", count(problems) > 0);
		check("package: and a fatal one", !careSendable(problems));
	} else {
		print("note: arCarePackage is set on this character, so the"
			+ " unset-package checks were skipped.", "olive");
	}

	if (failures > 0) {
		print(failures + " FAILED", "red");
	} else {
		print("care_packages: ok", "green");
	}
}
