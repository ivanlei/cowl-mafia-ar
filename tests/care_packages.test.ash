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
