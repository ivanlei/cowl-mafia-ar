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

	/* ---- what each of them got, and when ---- */

	// The Packages column reads these, and they cost nothing to collect: the
	// Outbox is walked in full on every page load anyway, so this is the
	// same chunks read for two more things.
	//
	// FOUR GIFTS AND THREE RECIPIENTS, because 105 has two. That is the
	// whole reason the gifts are a flat list and not a map keyed by who:
	// "how many has this person had" is the question the column answers.
	checkInt("gifts: one per marked message, not per recipient",
		count(sent.gifts), 4);
	checkInt("gifts: the one who had two", count(careGiftsFor(sent, 105)), 2);
	checkInt("gifts: the ones who had one", count(careGiftsFor(sent, 101)), 1);
	checkInt("gifts: and somebody who had none",
		count(careGiftsFor(sent, 999)), 0);

	care_gift [int] theirs = careGiftsFor(sent, 101);
	check("gifts: the date is KoL's own words",
		theirs[0].when.contains_text("November 08, 2026"));
	check("gifts: and it parsed into a number of days", theirs[0].days >= 0);
	checkString("gifts: what was in it", theirs[0].what, "soda water");

	// A GIFT BOX HIDES ITS CONTENTS and this does not pretend otherwise: the
	// Outbox lists the wrapper and nothing about what is inside it, so a
	// wrapped package reads as the box it went in.
	care_gift [int] wrapped = careGiftsFor(sent, 105);
	check("gifts: a wrapped one reads as the box",
		wrapped[0].what.contains_text("wrapper") || wrapped[1].what.contains_text("wrapper"));

	// Meat is "You gain 11 Meat." and not an acquire line at all, so it is
	// matched separately or it is silently dropped from every package that
	// carries any.
	checkString("gifts: Meat alone", careGiftContents(
		"<td>You gain 11 Meat.</td>"), "11 Meat");
	checkString("gifts: an item and Meat together", careGiftContents(
		"You acquire an item: <b>soda water</b> ... You gain 250 Meat."),
		"soda water, 250 Meat");
	checkString("gifts: a plural acquire keeps its count", careGiftContents(
		"You acquire <b>2 love songs of smoldering passion</b>"),
		"2 love songs of smoldering passion");
	// KoL wraps a long name and leaves the break's space behind in the text.
	checkString("gifts: a name broken across a line is put back together",
		careGiftContents("You acquire an item: <b>less-than-three- shaped box</b>"),
		"less-than-three-shaped box");
	checkString("gifts: nothing attached is nothing, not a stray comma",
		careGiftContents("<td>just words</td>"), "");

	// TWO WEEKS IS THE WINDOW, which matters for the Saved box: the Outbox
	// deletes itself after a fortnight and Saved never does, so without the
	// filter a package saved last winter would read as received recently.
	checkInt("gifts: the window is a fortnight", CARE_RECENT_DAYS, 14);
	care_sent old;
	old.read = true;
	care_gift stale;
	stale.who = 101;
	stale.when = "January 01, 2026";
	stale.days = CARE_RECENT_DAYS + 1;
	stale.what = "soda water";
	old.gifts[0] = stale;
	checkInt("gifts: one older than the window is not counted",
		count(careGiftsFor(old, 101)), 0);
	old.gifts[0].days = CARE_RECENT_DAYS;
	checkInt("gifts: and one exactly on it is",
		count(careGiftsFor(old, 101)), 1);
	// A date KoL writes in a shape careDaysSince cannot read comes back as
	// -1, and dropping those would undercount somebody silently -- which is
	// the opposite of what a column against double-sending should do.
	old.gifts[0].days = -1;
	checkInt("gifts: an unreadable date counts rather than vanishing",
		count(careGiftsFor(old, 101)), 1);

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

	// TWO ROWS THAT BOTH HAVE days = -1 AND MEAN DIFFERENT THINGS. This pair
	// is what pins the order of carePlan's verdict ladder: somebody in
	// Valhalla answered, somebody unreadable did not, and a ladder that tests
	// `days < 0` first calls the astral spirit unreadable and is wrong in a
	// way no other check here notices.
	standIn[3].who = 904;
	standIn[3].name = "In Valhalla";
	standIn[3].rank = "Member";
	standIn[3].savedAt = nowSeconds;
	standIn[3].format = CARE_ROSTER_FORMAT;

	standIn[4].who = 905;
	standIn[4].name = "Would Not Parse";
	standIn[4].rank = "Member";
	standIn[4].savedAt = nowSeconds;
	standIn[4].format = CARE_ROSTER_FORMAT;

	standInLogins[904].looked = true;
	standInLogins[904].lastLogin = CARE_ASTRAL_LOGIN;
	standInLogins[904].days = -1;
	standInLogins[904].fetchedAt = nowSeconds;
	standInLogins[904].format = CARE_LOGIN_FORMAT;

	standInLogins[905].looked = true;
	standInLogins[905].lastLogin = "";
	standInLogins[905].days = -1;
	standInLogins[905].fetchedAt = nowSeconds;
	standInLogins[905].format = CARE_LOGIN_FORMAT;

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
		check("window: a looked-up astral row is not queued again",
			!(queued contains 904));

		// THE VERDICT LADDER, over the same stand-ins. carePlan() reads the
		// mailbox live, which is two requests and is why this is the only
		// place it is called here.
		string [int] verdictOf;
		foreach i, r in carePlan() verdictOf[r.member.who] = r.verdict;

		checkString("plan: somebody in Valhalla is astral, not unreadable",
			verdictOf[904], CARE_ASTRAL);
		checkString("plan: and a profile that would not parse still is",
			verdictOf[905], CARE_UNKNOWN);
		checkString("plan: a fresh login inside the window would get one",
			verdictOf[901], CARE_WOULD);
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

	/* ---- what is in a package ---- */

	// THE ITEM WITH A COMMA IN ITS NAME is the whole reason the Package box
	// does not simply join its rows with commas. COwliCK holds four such
	// items right now, all giftable; this is one of them. Named through
	// to_item rather than as $item[...] so the comma cannot be read as
	// anything but part of the name.
	item awkward = "Oh, the Humanitini".to_item();
	check("package: the awkward test item exists", awkward != $item[none]);
	check("package: and its name really does have a comma in it",
		awkward.to_string().contains_text(","));

	care_part one = careOnePart("3 soda water");
	checkInt("part: the leading count comes off", one.qty, 3);
	checkString("part: and the rest is the name", one.named, "soda water");
	check("part: which resolves", one.what == $item[soda water]);

	one = careOnePart("  soda water  ");
	checkInt("part: no count means one", one.qty, 1);
	check("part: and the spaces are trimmed", one.what == $item[soda water]);

	one = careOnePart("nonsense widget of nope");
	check("part: an unknown name resolves to nothing", one.what == $item[none]);
	checkString("part: and is kept so a refusal can name it",
		one.named, "nonsense widget of nope");

	// The two readers. Same entries, different separator, and that is the
	// point: the stored form is KoLmafia's comma list and the wire form from
	// the browser is one per line, because a comma list cannot carry the item
	// above.
	checkInt("parts: a stored comma list",
		count(carePackageParts("3 soda water, 1 spices")), 2);
	checkInt("parts: blanks between commas are not entries",
		count(carePackageParts("3 soda water, , ,")), 1);
	checkInt("lines: what the Package box sends",
		count(carePartsFromLines("3 soda water\n1 spices")), 2);
	checkInt("lines: and a blank line is not an entry",
		count(carePartsFromLines("3 soda water\n\n")), 1);

	// THE ROUND TRIP, which is the test this whole pair of formats exists
	// for. Typed in the box, stored, read back: the same item, the same
	// count, and not two entries that resolve to nothing.
	string stored = carePackageList(carePartsFromLines("2 soda water\n1 "
		+ awkward.to_string()));
	check("round trip: the awkward name is stored as its id",
		stored.contains_text("[" + awkward.to_int() + "]"));
	check("round trip: so the stored list has one comma, the separator",
		count(split_string(stored, ",")) == 2);

	care_part [int] back = carePackageParts(stored);
	checkInt("round trip: two entries come back", count(back), 2);
	check("round trip: the ordinary one survives", back[0].what == $item[soda water]);
	checkInt("round trip: with its count", back[0].qty, 2);
	check("round trip: and so does the awkward one", back[1].what == awkward);
	checkInt("round trip: with its count too", back[1].qty, 1);

	// WHAT THE SUMMARY SAYS, which is not what is stored. The first time the
	// summary was handed a bracketed id it printed "190x (2 soda water,
	// 1 [5590])" -- true, correct, and no use to anybody.
	checkString("text: the id is read back out as a name",
		carePackageText(stored), "2 soda water, 1 " + awkward);
	checkString("text: and an ordinary list is unchanged",
		carePackageText("3 soda water"), "3 soda water");
	check("text: nothing a reader sees is in brackets",
		!carePackageText(stored).contains_text("["));

	// An ordinary name is NOT written as an id: the preference is meant to
	// stay something you can read and set from the gCLI.
	check("round trip: an ordinary name is written as a name",
		carePackageList(carePartsFromLines("1 soda water")) == "1 soda water");

	// A quantity of zero is written out rather than quietly dropped, so that
	// careBadValue() gets to refuse it. Filtering it here made the rule
	// unreachable and a row typed as 0 vanished without a word.
	check("round trip: a zero is kept for the validator to refuse",
		carePackageList(carePartsFromLines("0 soda water")) == "0 soda water");

	/* ---- what the Config and Package boxes may write ---- */

	boolean [string] settable = careSettable();
	checkInt("settable: five settings and no more", count(settable), 5);
	check("settable: the days", settable contains CARE_DAYS);
	check("settable: the places", settable contains CARE_SOURCES);
	check("settable: the note", settable contains CARE_NOTE);
	check("settable: the package", settable contains CARE_PACKAGE);
	check("settable: the Meat", settable contains CARE_MEAT);
	// Shown by the Config box and not edited there, which is what was asked
	// for: the roster's own rank list is how you find out how one is spelled.

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

	checkString("meat: a number is fine", careBadValue(CARE_MEAT, "500"), "");
	// Zero and empty both mean "no Meat", and clearing the box is how you say
	// so -- being told off for emptying a box you wanted empty is no answer.
	checkString("meat: zero is fine", careBadValue(CARE_MEAT, "0"), "");
	checkString("meat: empty is fine", careBadValue(CARE_MEAT, ""), "");
	check("meat: negative is not", careBadValue(CARE_MEAT, "-5") != "");
	check("meat: and a word is not", careBadValue(CARE_MEAT, "lots") != "");

	// The package is validated in its STORED form, which is what
	// ar_care_prefs.ash converts the box's lines to before checking -- so
	// what is checked is exactly what will be written.
	checkString("package: empty is fine, that is no items",
		careBadValue(CARE_PACKAGE, ""), "");
	checkString("package: a real giftable item is fine",
		careBadValue(CARE_PACKAGE, "3 soda water"), "");
	checkString("package: and so is the awkward one, by its id",
		careBadValue(CARE_PACKAGE, "1 [" + awkward.to_int() + "]"), "");
	check("package: an unknown name is refused",
		careBadValue(CARE_PACKAGE, "1 nonsense widget of nope") != "");
	check("package: a quantity of zero is refused",
		careBadValue(CARE_PACKAGE, "0 soda water") != "");

	// WHICH ROW, because the package saves as a whole and one bad row
	// refuses every good one with it. The first version said only "That is
	// not an item", which reads as being about the row you just touched --
	// a typo left in row one refused a good row two and pointed at it.
	check("package: the refusal names the row, not the last one touched",
		careBadValue(CARE_PACKAGE, "1 nonsense widget of nope, 1 soda water")
			.contains_text("Item 1"));
	check("package: and counts from the first",
		careBadValue(CARE_PACKAGE, "1 soda water, 1 nonsense widget of nope")
			.contains_text("Item 2"));
	check("package: a bad quantity says which one too",
		careBadValue(CARE_PACKAGE, "1 soda water, 0 spices").contains_text("Item 2"));
	// Still never repeats back what was sent.
	check("package: and never echoes the name back",
		!careBadValue(CARE_PACKAGE, "1 nonsense widget of nope")
			.contains_text("nonsense"));

	// A bound item cannot leave however it is packed, so offering to send one
	// is offering a refusal. The Package box does not even suggest them.
	item bound = $item[Boris's key];
	if (bound != $item[none] && !bound.is_giftable()) {
		check("package: an item that cannot be sent is refused",
			careBadValue(CARE_PACKAGE, "1 " + bound) != "");
	}

	// FIVE, BECAUSE THAT IS WHAT A GIFT BOX HOLDS, and anyone in Hardcore or
	// Ronin can only be sent a gift box. Refused here as well as reported by
	// carePackageProblems(), so the page's own controls cannot walk into a
	// state they then complain about.
	string five = "1 soda water, 1 spices, 1 tiny plastic sword, 1 cherry, 1 lime";
	checkString("package: five different items is allowed",
		careBadValue(CARE_PACKAGE, five), "");
	check("package: six is not",
		careBadValue(CARE_PACKAGE, five + ", 1 olive") != "");

	check("write: a setting the box does not carry is refused by the rule too",
		careBadValue("arTicketItems", "anything") != "");

	/* ---- somebody in Valhalla ---- */

	// THE BUG THIS IS HERE FOR. An astral spirit's profile has no Account
	// Created and no Last Login on it -- KoL serves the name, the id, "Level"
	// and "Astral Spirit", and nothing else. careLooksLikeProfile() correctly
	// says that is not a profile, and the answer was then never cached, so the
	// member could never leave the scan queue: the button stuck on "Continue
	// looking up (1 to go)" for ever and the page blamed KoLmafia for a server
	// that had answered 200 with exactly what it meant to send. Found against
	// the live clan, 2026-11-21.
	string astralPage = "<td valign=center><b>Someone</b> (#1)<br>Level "
		+ "<img src=\"/images/otherimages/inf_large.gif\"><br>Astral Spirit</td>";
	string astralReal = "<img src=\"/images/otherimages/spirit.gif\" width=60 "
		+ "height=100>" + astralPage;

	check("astral: the stub is not a profile", !careLooksLikeProfile(astralReal));
	check("astral: but it is recognised", careLooksLikeAstral(astralReal));

	// ANCHORED ON KoL'S OWN IMAGE, not on the words. "Astral Spirit" is a
	// phrase a player can type into their own profile text, and a real profile
	// matched as astral would lose a last login this page could have read.
	check("astral: the words alone are not enough", !careLooksLikeAstral(astralPage));
	check("astral: a real profile is never read as astral",
		!careLooksLikeAstral(profile));
	check("astral: and is still read as a profile", careLooksLikeProfile(profile));

	// WHAT careLastLogin ACTUALLY BRANCHES ON. It cannot be called without a
	// live KoL, so without naming this decision the fix is one careless edit
	// from being undone with nothing failing: reverting it to
	// careLooksLikeProfile() alone is exactly the stuck queue again.
	check("answered: a real profile is an answer", careProfileAnswered(profile));
	check("answered: so is an astral stub", careProfileAnswered(astralReal));
	check("answered: an empty page is not", !careProfileAnswered(""));
	check("answered: and nor is a page that is neither",
		!careProfileAnswered("<html><body>Nothing here.</body></html>"));

	// Stored in the lastLogin field rather than in a new one, so the held file
	// keeps its shape and a clan already walked is not thrown away.
	checkInt("astral: has no number of days to give",
		careDaysSince(CARE_ASTRAL_LOGIN), -1);
	checkString("astral: and the word is the one COwliCK asked for",
		CARE_ASTRAL_LOGIN, "astral");

	// COwliCK, 2026-11-21: "disable send to them but with the checkbox we've
	// added they can be sent to."
	check("astral: starts unticked", !careTickedByDefault(CARE_ASTRAL));
	check("astral: but is yours to tick", careTickable(CARE_ASTRAL));
	check("astral: and says where they are",
		careVerdictLabel(CARE_ASTRAL) != CARE_ASTRAL
		&& careVerdictLabel(CARE_ASTRAL) != "");

	/* ---- who may be ticked, and who starts ticked ---- */

	// The Send column replaced eight verdict headings with one tick per row
	// (COwliCK, 2026-11-21), so these two predicates are the whole of what
	// that column means.
	check("tick: the eligible are tickable", careTickable(CARE_WOULD));
	check("tick: and start ticked", careTickedByDefault(CARE_WOULD));

	// YOURS TO OVERRULE: every one of these is this page's own opinion or a
	// gap in what it knows, and you may know better.
	check("tick: not logged in lately is yours to tick", careTickable(CARE_QUIET));
	check("tick: an unreadable profile is yours to tick", careTickable(CARE_UNKNOWN));
	check("tick: one not looked up yet is yours to tick", careTickable(CARE_PENDING));
	check("tick: none of the three starts ticked",
		!careTickedByDefault(CARE_QUIET) && !careTickedByDefault(CARE_UNKNOWN)
		&& !careTickedByDefault(CARE_PENDING));

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
	everyVerdict[4] = CARE_PENDING;
	everyVerdict[5] = CARE_UNKNOWN;
	everyVerdict[6] = CARE_SELF;
	everyVerdict[7] = CARE_ASTRAL;
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
