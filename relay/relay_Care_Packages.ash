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
// THIS PAGE SENDS NOTHING. There is no send endpoint in this repository at
// all, so there is nothing here that could. The Send column is the selection
// that the sending will one day read; the sending gets its own file and its
// own look at.
//
// ar_care.ash does the reading and the deciding; this file only draws.
//
// TWO KoL SECTION BOXES, Config and Clan Members (ar_box.ash). KoL heads every
// section of every page the same way and a page of ours that invents its own
// heading does not look like the game it is part of. They fold, which is what
// a 239-row table wants on an iPad.
//
// SERVER-RENDERED, WITH CONTROLS. Everything on the page is written here, in
// ASH -- every verdict, every count, the price of a send -- and ar_care.js
// only drives the look-up, saves the three Config settings, and keeps the
// ticked count. A second renderer in JavaScript would be the thing that
// disagreed with this one, which is why a Config change that re-decides the
// table reloads the page rather than redrawing it.
//
// NOTHING IS DRAWN RAW. Names, ranks and the note come from outside and go
// through careHtml/careAttr; the reasoning is at the top of ar_care.ash.

import <ar_care.ash>
import <ar_assets.ash>
import <ar_box.ash>

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

// One line of the Package box: a quantity and an item, like KoL's "Send: [1]
// [type to find an item]".
//
// THE SAME MARKUP FOR A SAVED ROW AND AN EMPTY ONE, which is what lets
// ar_care.js clone a row without knowing anything about how one is built: the
// + copies the last one and clears it. An empty row is one whose item box is
// empty, here and in the JS, and that is also how a row is deleted.
void careItemRow(buffer out, int qty, string named) {
	out.append("<div class='care-row'>");
	out.append("<input class='care-qty care-number' type='number' min='1' step='1'"
		+ " value=" + careAttr(qty + "") + ">");
	out.append("<input class='care-item care-text' type='text' list='care-items'"
		+ " autocomplete='off' spellcheck='false'"
		+ " placeholder='type to find an item'"
		+ " value=" + careAttr(named) + ">");
	out.append("</div>");
}

// One member's row: Name, Rank, Last Login, Send.
//
// ONE TABLE WHERE THERE WERE EIGHT SECTIONS. COwliCK asked for "List of
// Clannies (table): Name, Rank, Last Login, Send (checkbox)", and the eight
// verdict headings that used to group the rows are gone with them -- so the
// verdict has to survive somewhere, or an empty tick box is a refusal with no
// reason attached. It survives in the Send cell: a tick for the ones that are
// getting one, a tick and a reason for the ones you may overrule, and the
// reason alone where there is nothing to overrule.
//
// EVERY UNTRUSTED STRING GOES THROUGH careHtml. The name and the rank are both
// typed by whoever runs the clan. See the top of ar_care.ash.
void careRow(buffer out, care_row r) {
	boolean tickable = careTickable(r.verdict);

	out.append("<tr class='care-row care-" + r.verdict + "'>");

	out.append("<td class='care-who'><a href=" + careAttr("showplayer.php?who=" + r.member.who) + ">");
	out.append(careHtml(r.member.name));
	out.append("</a></td>");

	out.append("<td class='care-rank'>" + careHtml(r.member.rank) + "</td>");

	out.append("<td class='care-seen'>");
	if (r.lastLogin != "") {
		out.append(careHtml(r.lastLogin));
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

	out.append("<td class='care-send'>");
	if (tickable) {
		// THE STATE IS THE ATTRIBUTE AND NOTHING ELSE DECIDES IT. careTickable
		// and careTickedByDefault are in ar_care.ash and are the one place the
		// rule is written; ar_care.js counts what is checked in the document
		// and never works out who may be.
		out.append("<input type='checkbox' class='care-tick'"
			+ (careTickedByDefault(r.verdict) ? " checked" : "") + ">");
	}
	// The reason, except for the one verdict that needs none: a ticked box in
	// a Send column already says "would get one", and printing it beside every
	// one of a hundred and ninety ticks is noise where the exceptions are the
	// thing to see.
	if (r.verdict != CARE_WOULD) {
		out.append("<span class='care-why'>" + careVerdictLabel(r.verdict) + "</span>");
	}
	out.append("</td>");

	out.append("</tr>");
}

// The rows, in three groups: ticked, then yours to tick, then locked.
//
// ROSTER ORDER WITHIN EACH GROUP, which is what carePlan() already returns and
// is worth keeping on purpose: KoL serves the roster grouped by rank, so this
// keeps the ranks together and makes the Rank column worth reading down.
// Alphabetical would scatter them for the sake of a name you can find with the
// browser's own search.
void careRows(buffer out, care_row [int] rows) {
	foreach i, r in rows {
		if (careTickedByDefault(r.verdict)) careRow(out, r);
	}
	foreach i, r in rows {
		if (!careTickedByDefault(r.verdict) && careTickable(r.verdict)) careRow(out, r);
	}
	foreach i, r in rows {
		if (!careTickable(r.verdict)) careRow(out, r);
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
	// This page's own stylesheets and nothing else -- it is served on its own
	// rather than decorated into one of KoL's, so it carries no other. Light
	// and dark live in them, the same way the anti-raffle page does it. The
	// section box first, so a rule of this page's can override one of its.
	out.append(arStyle("ar_box.css"));
	out.append(arStyle("ar_care.css"));
	// The hash ar_care_scan.ash checks, the same way relay_Anti_Raffle.ash does
	// it: without it a page cannot ask KoLmafia for anything.
	out.append("<script type='text/javascript'>var arPwd = \"" + my_hash() + "\";</script>\n");
	out.append("</head>\n<body>\n<div id='care'>\n");

	out.append("<h1>Care Packages</h1>\n");

	/* ---- anything wrong with it ---- */

	// ABOVE BOTH BOXES rather than inside one of them. carePackageProblems()
	// answers about the package and about the roster in the one list -- "no
	// package set yet" belongs to Config, "no clan roster is held yet" to Clan
	// Members -- and splitting it across the two means giving every problem a
	// home it does not otherwise need. What is wrong comes first either way.
	if (count(problems) > 0) {
		out.append("<ul class='care-problems'>");
		foreach i, p in problems {
			out.append("<li class='" + (p.fatal ? "care-fatal" : "care-warn") + "'>");
			out.append(p.what);
			out.append("</li>");
		}
		out.append("</ul>\n");
	}

	/* ---- what is configured ---- */

	// THREE OF THESE FIVE ROWS ARE NOW CONTROLS, which is the other half of
	// what COwliCK asked for on 2026-11-21 and the first time this page writes
	// anything. Each one saves itself on change against ar_care_prefs.ash --
	// no Save button, the way the anti-raffle's settings already work -- and
	// the two that change what the table says reload the page afterwards,
	// because every verdict in it is decided server-side and a second
	// renderer in JavaScript is the thing this page is built to avoid.
	//
	// The other two are read-only on purpose. The package is an item list that
	// wants parsing against real item names, which is its own job; the skipped
	// ranks are still typed into the gCLI, and the roster's own rank list at
	// the foot of the next box is how you find out how one is spelled.
	out.append(arBoxStart("Config"));

	out.append("<table class='care-setup'>");

	out.append("<tr><td class='care-label'>Active Means</td><td>");
	out.append("logged in within <input id='care-days' class='care-number'"
		+ " type='number' min='1' step='1' value=" + careAttr(careDays() + "") + "> days");
	out.append("</td></tr>");

	out.append("<tr><td class='care-label'>Gather Items From</td><td class='care-places'>");
	boolean [string] on = careSources();
	foreach i, place in careAllSources() {
		out.append("<label><input type='checkbox' class='care-place' data-place="
			+ careAttr(place) + (on contains place ? " checked" : "") + "> ");
		out.append(careHtml(careSourceName(place)));
		out.append("</label>");
	}
	out.append("</td></tr>");

	out.append("<tr><td class='care-label'>Ranks Skipped</td><td>");
	out.append(get_property(CARE_SKIP) == ""
		? "<i>none</i>" : careHtml(get_property(CARE_SKIP)));
	out.append("</td></tr>");

	out.append("</table>\n");
	out.append("<div id='care-config-said' class='care-said'></div>\n");

	out.append(arBoxEnd() + "\n");

	/* ---- what is in a package ---- */

	// KoL'S OWN kmail FORM, as closely as this can manage. COwliCK,
	// 2026-11-21, pointing at Send a Message: "very like the kmail item
	// sending UI. lets you select items from dropdown that autocompletes.
	// let's you add more drop downs. lets you select quantity of items. lets
	// you select an amount of meat." The note came here from Config in the
	// same breath -- "to look more like kmail send to" -- and it belongs
	// here: this box is now the whole of what a recipient gets.
	//
	// A ROW PER ITEM ALREADY SET, PLUS AN EMPTY ONE, so the common case needs
	// no press at all and the + is for the second item onwards, the way KoL's
	// is. An empty row is not in the preference, so a reload brings back
	// exactly the items that are set and one more blank.
	out.append(arBoxStart("Package"));

	out.append("<div id='care-rows' class='care-rows'>");
	care_part [int] parts = carePackageParts(carePackage());
	foreach i, p in parts {
		careItemRow(out, p.qty, p.what == $item[none] ? p.named : p.what.to_string());
	}
	careItemRow(out, 1, "");
	out.append("</div>\n");

	// The suggestions, filled by ar_care.js from ar_care_items.ash. Empty in
	// the served page on purpose: it is a couple of thousand <option> tags on
	// this character, which is a third of the page's weight for something the
	// browser only needs once the box is focused.
	out.append("<datalist id='care-items'></datalist>\n");

	out.append("<div class='care-row'>");
	out.append("<button id='care-add-row' type='button' class='care-plus'>+ add another</button>");
	out.append("</div>\n");

	out.append("<table class='care-setup'>");
	out.append("<tr><td class='care-label'>Send Meat</td><td>");
	out.append("<input id='care-meat' class='care-number' type='number' min='0'"
		+ " step='1' value=" + careAttr(careMeat() + "") + ">");
	out.append("</td></tr>");

	// THE EFFECTIVE NOTE, not the raw preference: careNote() answers the
	// default sentence for an unset one, and a box that is empty when the
	// kmail will not be is a box that lies about what is going to be sent.
	// Clearing it is still how you get the default back -- careBadValue()
	// allows an empty value for exactly that.
	out.append("<tr><td class='care-label'>Package Note</td><td>");
	out.append("<input id='care-note-text' class='care-text' type='text'"
		+ " value=" + careAttr(careNote()) + ">");
	out.append("</td></tr>");
	out.append("</table>\n");

	out.append("<div id='care-package-said' class='care-said'></div>\n");

	out.append(arBoxEnd() + "\n");

	/* ---- the clan ---- */

	out.append(arBoxStart("Clan Members"));

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
	// Renamed from care-note when the note became a text box in Config: two
	// things called "the note" on one page, one of them a kmail's words and
	// the other a scan's error line, is a collision waiting for whoever edits
	// this next.
	out.append("<span id='care-said' class='care-said'></span>");
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
			// carePackageText(), not carePackage(): the stored form can hold a
			// bracketed id for an item whose name has a comma in it, and
			// "190x (2 soda water, 1 [5590])" is not a sentence.
			out.append(would + "&times; (" + careHtml(carePackageText(carePackage())) + ")");
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

	/* ---- the roster ---- */

	// NOTHING HELD IS NOTHING TO DRAW, rather than a header row over an empty
	// table -- which is what this looked like before any scan had run, and
	// reads as a table that failed to load rather than as a page waiting to be
	// asked.
	if (count(rows) > 0) {
		// HOW MANY ARE TICKED, and the one thing on this page that is not
		// written here. It has to follow the ticks as they are set, which
		// nothing server-side can do -- so ar_care.js owns the whole sentence
		// and fills this on load by counting the document. An empty span
		// rather than a seeded one, because a server-written count and a
		// JS-written count are two renderers of the same number and would
		// eventually disagree about it.
		out.append("<p class='care-ticked'><span id='care-ticked'></span></p>\n");

		// THE HEADER CELLS CARRY THE SAME CLASSES AS THE BODY'S, which is not
		// decoration: the narrow-pane rule hides .care-rank, and a header
		// written as a bare <td> stayed behind as a "Rank" column heading
		// over nothing at all.
		out.append("<table class='care-list'>");
		out.append("<tr class='care-head'><td class='care-who'>Name</td>"
			+ "<td class='care-rank'>Rank</td>"
			+ "<td class='care-seen'>Last Login</td>"
			+ "<td class='care-send'>Send</td></tr>");
		careRows(out, rows);
		out.append("</table>\n");
	}

	/* ---- what there is to skip ---- */

	// UNDER THE TABLE, not over it. This is a reference list -- it is where
	// you find out how a rank is spelled before typing it into the gCLI, and
	// a skipped one is struck through so the list doubles as a readout of
	// arCareSkipRanks -- and a reference list above the answer is a reference
	// list in the way of it. Shown whether or not anything is skipped yet,
	// because the spelling is the thing it is mostly consulted for.
	if (careRosterRead) {
		boolean [string] skipped = careSkipRanks();
		out.append("<p class='care-ranks'><span class='care-label'>Ranks on the roster:</span> ");
		boolean first = true;
		foreach rank, n in careRankCounts(rows) {
			if (!first) out.append(", ");
			first = false;
			boolean off = skipped contains rank.to_lower_case();
			out.append("<span class='" + (off ? "care-rank-off" : "care-rank-on") + "'>");
			out.append(careHtml(rank) + " (" + n + ")");
			out.append("</span>");
		}
		out.append("</p>\n");
	}

	out.append(arBoxEnd() + "\n");

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
