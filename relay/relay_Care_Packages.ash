// relay_Care_Packages.ash -- care packages for your clan, on a page of its own.
// KoLmafia lists it in the relay browser's Scripts menu because of the relay_
// prefix on the name.
//
// Sending one to everybody who still plays is hand work: read however many
// pages of roster, open each member's profile for a last login, remember who
// you already sent to, compose a kmail each. On a clan of a couple of hundred
// it does not get done. This answers who is active, who has already had one,
// and what they would get -- and it answers the middle question out of your own
// sent mail rather than a list of its own, because a list of its own can
// disagree with the game.
//
// THIS PAGE SENDS NOTHING, and not as a promise: there is no send endpoint
// beside it, no form on the page and no script. There is nothing here that
// could. The sending gets its own file and its own look at.
//
// ar_care.ash does the reading and the deciding; this file only draws.
//
// SERVER-RENDERED, WITH ONE CONTROL. Everything on the page is written here, in
// ASH -- the eight verdict sections, the counts, the price of a send -- and
// ar_care.js only drives the look-up and reloads this page when it finishes. A
// second renderer in JavaScript would be the thing that disagreed with this
// one.

import <ar_care.ash>
import <ar_assets.ash>

// THIS PAGE FETCHES NO PROFILES, which is the change of 2026-11-21 and the
// reason there is no budget here any more. There was a CARE_BUDGET = 80: every
// load walked the roster and spent eighty profile fetches inside the render,
// about eight seconds of blank browser, and then printed a sentence asking you
// to reload for the next eighty. COwliCK: "it started loading profiles when the
// page loaded, stopped midway, didn't well indicate what it was doing."
//
// Now the roster and the last logins are held on disk for careHoldDays() and
// this page only draws them; the look-up is a button, done a batch at a time
// with a progress line, in ar_care.js against ar_care_scan.ash. What a load
// still costs is the mailbox -- two requests -- because who has already had one
// is the one answer kept live rather than held.

// How old a held snapshot is, in the words the header uses. Hours below a day,
// because "0 days ago" for something taken twenty minutes ago reads as broken.
string careSnapshotAgeText() {
	int age = careSnapshotAgeSeconds();
	if (age < 0) return "";
	if (age < 60) return "just now";
	if (age < 60 * 60) {
		int mins = age / 60;
		return mins + (mins == 1 ? " minute ago" : " minutes ago");
	}
	if (age < 24 * 60 * 60) {
		int hours = age / (60 * 60);
		return hours + (hours == 1 ? " hour ago" : " hours ago");
	}
	int days = age / (24 * 60 * 60);
	return days + (days == 1 ? " day ago" : " days ago");
}

string careVerdictLabel(string verdict) {
	switch (verdict) {
		case CARE_WOULD:    return "would get one";
		case CARE_HAD:      return "already had one";
		case CARE_QUIET:    return "not logged in lately";
		case CARE_INACTIVE: return "account inactive";
		case CARE_SKIPPED:  return "rank skipped";
		case CARE_PENDING:  return "not looked up yet";
		case CARE_UNKNOWN:  return "last login unreadable";
		case CARE_SELF:     return "you";
	}
	return verdict;
}

void careSection(buffer out, care_row [int] rows, string verdict, string heading) {
	int n = careCount(rows, verdict);
	if (n == 0) return;

	out.append("<tr class='care-section'><td colspan='4'><b>");
	out.append(heading);
	out.append("</b> (" + n + ")</td></tr>");

	foreach i, r in rows {
		if (r.verdict != verdict) continue;
		out.append("<tr class='care-row care-" + verdict + "'>");
		out.append("<td class='care-who'><a href='showplayer.php?who=" + r.member.who + "'>");
		out.append(r.member.name);
		out.append("</a></td>");
		out.append("<td class='care-rank'>" + r.member.rank + "</td>");
		out.append("<td class='care-seen'>");
		if (r.lastLogin != "") {
			out.append(r.lastLogin);
			if (r.days == 0)      out.append(" <span class='care-ago'>(today)</span>");
			else if (r.days > 0)  out.append(" <span class='care-ago'>(" + r.days
				+ (r.days == 1 ? " day ago)" : " days ago)") + "</span>");
		} else if (r.verdict == CARE_HAD || r.verdict == CARE_SKIPPED
				|| r.verdict == CARE_INACTIVE) {
			// Deliberately not fetched: a member ruled out before the profile
			// step costs no request, so there is no last login to show and
			// none was wanted.
			out.append("<span class='care-ago'>not looked up</span>");
		} else {
			out.append("<span class='care-ago'>&mdash;</span>");
		}
		out.append("</td>");
		out.append("<td class='care-verdict'>" + careVerdictLabel(r.verdict) + "</td>");
		out.append("</tr>");
	}
}

void main() {
	// The plan FIRST, because carePackageProblems() reports on what the plan
	// could and could not read (careRosterRead / careSentRead) as well as on
	// the package itself. Asked the other way round it would answer about the
	// previous load, which is to say about nothing.
	care_row [int] rows = carePlan();
	care_problem [int] problems = carePackageProblems();
	int pending = careCount(rows, CARE_PENDING);
	int todo = careScanTodo();
	int snapshotAt = careSnapshotAt();

	buffer out;
	out.append("<!DOCTYPE html>\n<html><head>\n");
	out.append("<title>Care Packages</title>\n");
	out.append("<meta name='viewport' content='width=device-width, initial-scale=1'>\n");
	// This page's own stylesheet and nothing else -- it is served on its own
	// rather than decorated into one of KoL's, so it carries no other. Light
	// and dark live in there, the same way the anti-raffle page does it.
	out.append(arStyle("ar_care.css"));
	// The hash ar_care_scan.ash checks, the same way relay_Anti_Raffle.ash does
	// it: without it a page cannot ask KoLmafia for anything.
	out.append("<script type='text/javascript'>var arPwd = \"" + my_hash() + "\";</script>\n");
	out.append("</head>\n<body>\n<div id='care'>\n");

	out.append("<h1>Care Packages</h1>\n");

	/* ---- the look-up, and what is held ---- */

	// THE ONLY THING ON THIS PAGE THAT FETCHES ANYTHING, and it does it when
	// pressed. Three labels rather than one, because what the press will do
	// genuinely differs and a button that says "Look up" and then silently
	// fetches nothing (every login still inside the week) is the complaint this
	// whole change is answering.
	// start     walk the roster, then the profiles it owes
	// continue  profiles only -- the held roster is still good
	// again     forget everything held, then walk it all
	//
	// A STALE SNAPSHOT IS "start" AND NOT "continue", which is the case worth
	// spelling out: when the hold window has passed, every login has aged out
	// too, so a "continue" would correctly re-fetch all of them -- and quietly
	// go on using a roster that is a fortnight old, missing everyone who has
	// joined since and offering to send to everyone who has left.
	string mode = "start";
	string label = "Look up clan members";
	if (count(rows) > 0 && !careSnapshotFresh()) {
		mode = "start";
		label = "Look up again (what is held is out of date)";
	} else if (todo > 0 && count(rows) > 0) {
		mode = "continue";
		label = "Continue looking up (" + todo + " to go)";
	} else if (count(rows) > 0) {
		mode = "again";
		label = "Look up again";
	}

	out.append("<div class='care-scan'>");
	out.append("<button id='care-scan' type='button' data-mode='" + mode + "'>");
	out.append(label);
	out.append("</button>");
	// Hidden until a scan is running; ar_care.js shows it then. A Stop that is
	// always on screen is a Stop that looks pressable when there is nothing to
	// stop.
	out.append("<button id='care-stop' type='button' hidden>Stop</button>");
	out.append("<span id='care-progress' class='care-progress'></span>");
	out.append("<span id='care-note' class='care-note-line'></span>");
	out.append("</div>\n");

	// HOW OLD THE ANSWER IS, said on every load. A week-long hold is a real
	// trade -- a last login read six days ago can call somebody quiet who came
	// back on Tuesday -- and the honest way to hold data that long is to put
	// its age next to the conclusions drawn from it.
	out.append("<p class='care-held'>");
	if (snapshotAt == 0) {
		out.append("Nothing is held yet. Nothing on this page has been looked up.");
	} else {
		out.append("Roster and last logins taken <b>" + careSnapshotAgeText() + "</b>");
		out.append(", held for " + careHoldDays()
			+ (careHoldDays() == 1 ? " day" : " days"));
		if (!careSnapshotFresh()) {
			out.append(" &mdash; <span class='care-stale'>this is older than that, so it is "
				+ "out of date</span>");
		}
		out.append(".");
	}
	out.append("</p>\n");

	/* ---- what is configured ---- */

	out.append("<table class='care-setup'>");
	out.append("<tr><td class='care-label'>Active means</td><td>logged in within "
		+ careDays() + (careDays() == 1 ? " day" : " days") + "</td></tr>");
	out.append("<tr><td class='care-label'>Package</td><td>");
	out.append(carePackage() == "" ? "<i>not set</i>" : carePackage());
	if (careMeat() > 0) out.append((carePackage() == "" ? "" : ", ") + careMeat() + " Meat");
	out.append("</td></tr>");

	out.append("<tr><td class='care-label'>Packed from</td><td>");
	boolean firstPlace = true;
	foreach i, place in arAllSources() {
		if (!(careSources() contains place)) continue;
		if (!firstPlace) out.append(", ");
		firstPlace = false;
		out.append(place);
	}
	if (firstPlace) out.append("<i>nowhere</i>");
	out.append("</td></tr>");

	out.append("<tr><td class='care-label'>Ranks skipped</td><td>");
	out.append(get_property(CARE_SKIP) == "" ? "<i>none</i>" : get_property(CARE_SKIP));
	out.append("</td></tr>");
	out.append("<tr><td class='care-label'>Note</td><td>" + careNote() + "</td></tr>");
	out.append("</table>\n");

	/* ---- anything wrong with it ---- */

	if (count(problems) > 0) {
		out.append("<ul class='care-problems'>");
		foreach i, p in problems {
			out.append("<li class='" + (p.fatal ? "care-fatal" : "care-warn") + "'>");
			out.append(p.what);
			out.append("</li>");
		}
		out.append("</ul>\n");
	}

	/* ---- what would happen ---- */

	int would = careCount(rows, CARE_WOULD);
	out.append("<p class='care-summary'>");
	if (!careRosterRead) {
		// Never "0 of 0 clan members", which is what an empty response read as
		// before the roster could fail out loud. The reason is different now
		// that the roster is held rather than fetched per load: there is
		// nothing to read because nothing has been looked up, which is the
		// state a fresh install is in and is not an error.
		out.append("<b>No clan roster is held yet.</b> Press the button above.");
	} else if (!careSendable(problems)) {
		out.append("<b>Nothing to send yet.</b> " + would + " of "
			+ count(rows) + " clan members would be eligible.");
	} else {
		out.append("<b>" + would + "</b> of " + count(rows)
			+ " clan members would get a package");
		// What a bulk send actually costs, because most of a clan being
		// eligible is not obvious from the package on its own. The Meat is "up
		// to": a gift box is only bought for a recipient a plain kmail is
		// refused for, and whether someone is in Hardcore or Ronin is not
		// something this can see.
		if (careMeat() > 0) out.append(" &mdash; " + (careMeat() * would) + " Meat in all");
		if (carePackage() != "") {
			out.append(careMeat() > 0 ? ", plus " : " &mdash; ");
			out.append(would + "&times; (" + carePackage() + ")");
		}
		out.append(", and up to " + (would * 1000)
			+ " Meat of gift boxes for anyone in Hardcore or Ronin.");
	}
	out.append("</p>\n");

	// WHAT IS STILL UNKNOWN, and whose answer is the button above rather than a
	// reload. Was "this load spent its 80 profile fetches. Reload to continue",
	// which told you the page had decided to spend eight seconds of your time
	// and would like to do it again.
	if (pending > 0) {
		out.append("<p class='care-warn'>" + pending + " of these "
			+ (pending == 1 ? "has" : "have") + " not been looked up");
		if (todo > 0 && todo != pending) {
			// The two counts answer different questions and can differ: a row
			// is pending when the page has no fresh login for it, while the
			// queue also leaves out anyone the scan knows it need not fetch.
			out.append(", and the look-up owes " + todo);
		}
		out.append(". Nothing is fetched until you press the button.</p>\n");
	}

	// NO SEND BUTTON EXISTS IN THIS VERSION. Said out loud, because a page
	// about sending that shows a list and no button otherwise reads as broken.
	out.append("<p class='care-note'>This page does not send anything yet.</p>\n");

	/* ---- what there is to skip ---- */

	// Shown whether or not anything is skipped yet, because this is where you
	// find out how a rank is spelled. A skipped one is marked so the list
	// doubles as a readout of the setting.
	if (careRosterRead) {
		boolean [string] skipped = careSkipRanks();
		out.append("<p class='care-ranks'><span class='care-label'>Ranks on the roster:</span> ");
		boolean first = true;
		foreach rank, n in careRankCounts(rows) {
			if (!first) out.append(", ");
			first = false;
			boolean off = skipped contains rank.to_lower_case();
			out.append("<span class='" + (off ? "care-rank-off" : "care-rank-on") + "'>");
			out.append(rank + " (" + n + ")");
			out.append("</span>");
		}
		out.append("</p>\n");
	}

	/* ---- the roster ---- */

	// NOTHING HELD IS NOTHING TO DRAW, rather than a header row over an empty
	// table -- which is what this looked like before any scan had run, and
	// reads as a table that failed to load rather than as a page waiting to be
	// asked.
	if (count(rows) > 0) {
		out.append("<table class='care-list'>");
		out.append("<tr class='care-head'><td>Member</td><td>Rank</td><td>Last login</td><td></td></tr>");
		careSection(out, rows, CARE_WOULD,    "Would get one");
		careSection(out, rows, CARE_HAD,      "Already had one");
		careSection(out, rows, CARE_SKIPPED,  "Rank skipped");
		careSection(out, rows, CARE_QUIET,    "Not logged in lately");
		careSection(out, rows, CARE_PENDING,  "Not looked up yet");
		careSection(out, rows, CARE_INACTIVE, "Account inactive");
		careSection(out, rows, CARE_UNKNOWN,  "Last login unreadable");
		careSection(out, rows, CARE_SELF,     "You");
		out.append("</table>\n");
	}

	out.append("</div>\n");

	// Ordered plain tags, ar_ask.js first: ar_care.js reads window.arAsk when
	// its click handler runs, and relay_Anti_Raffle.ash loads the pair the same
	// way. This page had no script at all until the look-up became a button --
	// its header used to say "a page with no controls needs no script to work",
	// which was true of it and no longer is.
	out.append(arScript("ar_ask.js"));
	out.append(arScript("ar_care.js"));
	out.append("</body>\n</html>\n");
	out.write();
}
