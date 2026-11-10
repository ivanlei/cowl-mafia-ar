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
// Server-rendered, because a page with no controls needs no script to work.

import <ar_care.ash>
import <ar_assets.ash>

// HOW MANY PROFILES ONE PAGE LOAD MAY FETCH.
//
// The last login is only on each member's own profile, so a cold cache costs
// one request per member -- a couple of hundred on a large clan, and a profile
// page is about 80KB. That is more than a page load should spend, so it is
// spent from a budget and the page says what is left to do; a reload picks up
// where it stopped, and once the cache is warm every load spends none.
//
// 80 is about eight seconds, measured at roughly 100ms a profile. In a map
// because ASH passes an aggregate by reference and an int by value, and every
// row has to draw on the one budget.
int CARE_BUDGET = 80;

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
	int [int] budget;
	budget[0] = CARE_BUDGET;

	// The plan FIRST, because carePackageProblems() reports on what the plan
	// could and could not read (careRosterRead / careSentRead) as well as on
	// the package itself. Asked the other way round it would answer about the
	// previous load, which is to say about nothing.
	care_row [int] rows = carePlan(budget);
	care_problem [int] problems = carePackageProblems();
	int pending = careCount(rows, CARE_PENDING);

	buffer out;
	out.append("<!DOCTYPE html>\n<html><head>\n");
	out.append("<title>Care Packages</title>\n");
	out.append("<meta name='viewport' content='width=device-width, initial-scale=1'>\n");
	// This page's own stylesheet and nothing else -- it is served on its own
	// rather than decorated into one of KoL's, so it carries no other. Light
	// and dark live in there, the same way the anti-raffle page does it.
	out.append(arStyle("ar_care.css"));
	out.append("</head>\n<body>\n<div id='care'>\n");

	out.append("<h1>Care Packages</h1>\n");

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
		// before the roster could fail out loud.
		out.append("<b>The roster did not come back.</b> Nothing below is the truth.");
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

	if (pending > 0) {
		out.append("<p class='care-warn'>" + pending
			+ " still to look up &mdash; this load spent its " + CARE_BUDGET
			+ " profile fetches. Reload to continue; what is already looked up is cached.</p>\n");
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

	out.append("</div>\n</body>\n</html>\n");
	out.write();
}
