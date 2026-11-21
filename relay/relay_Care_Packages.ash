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
// THIS PAGE SENDS, as of 2026-11-21, which it spent its whole life until now
// saying it did not. The Send column is the selection and the button at the
// foot of the Care Package box is the send; ar_care_send.ash does it, a few
// recipients per request, and will not start without somebody ticked,
// something in the package and a note. It takes two presses.
//
// ar_care.ash does the reading and the deciding; this file only draws.
//
// TWO KoL SECTION BOXES, Care Package and Clan Members (ar_box.ash). KoL
// heads every section of every page the same way and a page of ours that
// invents its own heading does not look like the game it is part of. They
// fold, which is what a 239-row table wants on an iPad.
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
// SHAPED LIKE KoL'S OWN ROW, which is `<b>Send: <input size=2 value=1></b>
// <select>` with a bold + after it. The quantity is two characters wide
// because KoL's is, and because a package of more than ninety-nine of
// anything is not a thing anybody is typing by accident.
//
// NOT A <select>, though, and not the <datalist> this had first: the list has
// to sit under the box (COwliCK, 2026-11-21) and you have to be able to name
// an item you do not hold yet. ar_combo.js does both; the wrapper below is
// what it hangs the list off, and it has to be in the markup rather than
// made by the script so that cloning a row clones a whole control.
// EVERY ROW CARRIES ITS OWN BOLD "Send:", which is KoL's own shape and not a
// guess: its addlist() writes `<b>Send: <input size=2 value=1></b><select>`
// for each of the eleven rows it can add, so the label repeats down the
// stack rather than heading it once.
//
// NOT class='care-row'. That name belongs to a clan member's <tr> further
// down this file, and giving it to these rows as well put `display: flex` on
// every row of the member table -- which stopped being a table and laid each
// row out to fit its own contents, columns and all. COwliCK found it;
// I had it on screen twice and read past it.
void careItemRow(buffer out, int qty, string named, boolean withPlus) {
	out.append("<div class='care-send-row'>");
	out.append("<b class='care-send-label'>Send:</b>");
	out.append("<input class='care-qty' type='text' inputmode='numeric'"
		+ " size='2' value=" + careAttr(qty + "") + ">");
	out.append("<span class='ar-combo care-combo'>");
	out.append("<input class='care-item' type='text'"
		+ " autocomplete='off' spellcheck='false'"
		+ " placeholder='type to find an item'"
		+ " value=" + careAttr(named) + ">");
	out.append("</span>");
	// After the first row only, the way KoL's is: its + sits in the static
	// markup beside row one and the rows it adds carry none.
	if (withPlus) {
		out.append("<a id='care-add-row' class='care-plus' href='#'"
			+ " title='another item'><b>+</b></a>");
	}
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
	} else if (r.verdict == CARE_HAD || r.verdict == CARE_INACTIVE) {
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
		// data-who, because a tick is now a recipient: the send names ids,
		// so the browser has to be able to say which rows are ticked. The id
		// is in the profile link beside it too, but reading a recipient out
		// of an href is the kind of thing that breaks when the link changes.
		out.append("<input type='checkbox' class='care-tick' data-who='"
			+ r.member.who + "'"
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

	// WHAT THIS PAGE HAS SENT THEM LATELY, and what was in it. COwliCK,
	// 2026-11-21: "a final column in the player roster called 'packages'.
	// value is always: <#> received."
	//
	// ALWAYS A COUNT, even when it is nought, because a blank cell and a
	// cell saying none are different claims and only one of them is being
	// made here: the mailbox was read and this is what it said.
	//
	// It costs nothing to know. The Outbox is walked in full on every page
	// load already -- that is how "already had one" is decided -- so this
	// column is the same chunks read for two more things.
	care_gift [int] gifts = careGiftsFor(careSentRecord, r.member.who);
	out.append("<td class='care-gifts'>");
	if (count(gifts) > 0) {
		// A LINK ONLY WHEN THERE IS SOMETHING BEHIND IT. A pressable-looking
		// "0 received" that opens nothing is worse than plain text.
		out.append("<a href='#' class='care-gift-open'>"
			+ count(gifts) + " received</a>");
	} else {
		out.append("<span class='care-gift-none'>0 received</span>");
	}
	out.append("</td>");

	out.append("</tr>");

	// THE DETAIL, WRITTEN HERE AND HIDDEN, not fetched or composed when you
	// press. Everything about it is known at render time, the page has no
	// second renderer by design, and a row that unfolds instantly is the
	// whole difference between this and something that feels like a request.
	if (count(gifts) > 0) {
		out.append("<tr class='care-gift-row' hidden><td colspan='5'>");
		out.append("<ul class='care-gift-list'>");
		foreach i, g in gifts {
			out.append("<li><span class='care-gift-when'>"
				+ careHtml(g.when == "" ? "date unreadable" : g.when)
				+ "</span> ");
			// A wrapped package lists the box and not its contents: that is
			// all the Outbox records of it. Saying so beats showing the box
			// as though it were the present.
			out.append(g.what == ""
				? "<i>nothing the mailbox lists</i>"
				: careHtml(g.what));
			out.append("</li>");
		}
		out.append("</ul></td></tr>");
	}
}

// The rows, in roster order. All of them, in the order KoL lists them.
//
// NO GROUPING. This used to sort into three -- ticked, then yours to tick,
// then locked -- which put everybody who had already had a package at the
// bottom of a 239-row table, a long way from where they had been the last
// time you looked. COwliCK, 2026-11-21: "don't move people who already
// received a package to the bottom, keep them where they were."
//
// Roster order is also the order that makes the Rank column worth reading:
// KoL serves the roster grouped by rank, so leaving it alone keeps the ranks
// together. What the grouping was for -- seeing at a glance who is getting
// one -- the Send column now does in place, a tick per row, which is the
// better answer anyway because it does not move anything.
void careRows(buffer out, care_row [int] rows) {
	foreach i, r in rows {
		careRow(out, r);
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
	out.append(arStyle("ar_combo.css"));
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

	// ONE BOX, "Care Package", with what was Config at the top of it in the
	// order it was already in (COwliCK, 2026-11-21). The two halves answer
	// different questions -- who counts as active and where a package is
	// packed from, then what is in it -- but they are one decision and were
	// never worth two bars.
	//
	// EVERY CONTROL SAVES ITSELF on change against ar_care_prefs.ash, with no
	// Save button, the way the anti-raffle's settings already work. The ones
	// that change what the member table says reload the page afterwards,
	// because every verdict in it is decided server-side and a second
	// renderer in JavaScript is the thing this page is built to avoid.
	out.append(arBoxStart("Care Package"));

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

	out.append("</table>\n");
	out.append("<div id='care-config-said' class='care-said'></div>\n");

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

	// KoL'S OWN LAYOUT, in its own order: the whole form is inside a
	// <center>, the message comes first under a plain "Message:" on a line of
	// its own, then the Send rows with their bold labels, then a bold
	// "Send Meat:" with a size-5 box. COwliCK, 2026-11-21: "make it look more
	// like the kmail image. placement, layout, fonting."
	//
	// The note moved to the TOP with that, because that is where kmail's
	// message is. It was at the foot when the box was a settings table and
	// the order did not mean anything; now the box is a copy of a form whose
	// order is the thing being copied.
	out.append("<div class='care-kmail'>");

	// THE EFFECTIVE NOTE, not the raw preference: careNote() answers the
	// default sentence for an unset one, and a box that is empty when the
	// kmail will not be is a box that lies about what is going to be sent.
	// Clearing it is still how you get the default back -- careBadValue()
	// allows an empty value for exactly that.
	//
	// The label is plain rather than bold, like KoL's "Message:", which is
	// the one label on that form that is not in <b>.
	out.append("<div class='care-note-label'>Package Note:</div>");
	out.append("<textarea id='care-note-text' class='care-note-box' rows='8'"
		+ " spellcheck='true'>");
	out.append(careHtml(careNote()));
	out.append("</textarea>");

	// Left-aligned inside the centred block, so the quantity boxes line up
	// in a column down the stack and only the row carrying the + runs wider
	// -- which is what KoL's does too.
	out.append("<div id='care-rows' class='care-rows'>");
	care_part [int] parts = carePackageParts(carePackage());
	int row = 0;
	foreach i, p in parts {
		careItemRow(out, p.qty, p.what == $item[none] ? p.named : p.what.to_string(),
			row == 0);
		row = row + 1;
	}
	careItemRow(out, 1, "", row == 0);
	out.append("</div>");

	out.append("<div class='care-meat-line'><b>Send Meat:</b> ");
	out.append("<input id='care-meat' class='care-qty care-meat' type='text'"
		+ " inputmode='numeric' size='5' value=" + careAttr(careMeat() + "") + ">");
	out.append("</div>");

	out.append("<div id='care-package-said' class='care-said'></div>");

	/* ---- what would happen ---- */

	// WHAT A SEND WOULD COST, AND IT COUNTS THE TICKS. Every number in this
	// sentence is the number of recipients times something, and since the
	// Send column arrived that number is whatever is ticked in the browser --
	// which the server cannot know. COwliCK, 2026-11-21: "i unselected most
	// people - only 3 are selected - but the text claims 190 are selected and
	// miscalculates how much items/meat will be sent."
	//
	// So the SENTENCE is still written here and the NUMBERS in it are holes
	// ar_care.js fills from the live tick count. Which clauses appear depends
	// on the package and the Meat, not on the ticks, so that stays here too;
	// what crosses to the browser is three multiplications and the unit
	// costs they multiply, carried on the <p> itself.
	//
	// The alternative was composing the whole sentence in JavaScript, which
	// would put the package's own words, the gift-box caveat and the
	// Meat-or-no-Meat branching in a second renderer -- the exact thing the
	// rest of this page is arranged to avoid.
	int would = careCount(rows, CARE_WOULD);
	int CARE_GIFT_BOX = 1000;
	out.append("<p class='care-summary' id='care-summary'"
		+ " data-meat='" + careMeat() + "' data-box='" + CARE_GIFT_BOX + "'>");
	if (!careRosterRead) {
		// Never "0 of 0 clan members", which is what an empty response read as
		// before the roster could fail out loud. The reason is different now
		// that the roster is held rather than fetched per load: there is
		// nothing to read because nothing has been looked up, which is the
		// state a fresh install is in and is not an error.
		out.append("<b>No clan roster is held yet.</b> Press <b>Look up clan members</b> below.");
	} else if (!careSendable(problems)) {
		out.append("<b>Nothing to send yet.</b> " + would + " of "
			+ count(rows) + " clan members would be eligible.");
	} else {
		// Each hole is written with the value the ticks start at, so the
		// sentence is right before a line of script has run and right after.
		out.append("<b><span class='care-n'>" + would + "</span></b> of "
			+ count(rows) + " clan members would get a package");
		// What a bulk send actually costs, because most of a clan being
		// eligible is not obvious from the package on its own. The Meat is "up
		// to": a gift box is only bought for a recipient a plain kmail is
		// refused for, and whether someone is in Hardcore or Ronin is not
		// something this can see.
		if (careMeat() > 0) {
			out.append(" &mdash; <span class='care-meat-all'>"
				+ (careMeat() * would) + "</span> Meat in all");
		}
		if (carePackage() != "") {
			out.append(careMeat() > 0 ? ", plus " : " &mdash; ");
			// carePackageText(), not carePackage(): the stored form can hold a
			// bracketed id for an item whose name has a comma in it, and
			// "190x (2 soda water, 1 [5590])" is not a sentence.
			out.append("<span class='care-n'>" + would + "</span>&times; ("
				+ careHtml(carePackageText(carePackage())) + ")");
		}
		out.append(", and up to <span class='care-box-all'>"
			+ (would * CARE_GIFT_BOX)
			+ "</span> Meat of gift boxes for anyone in Hardcore or Ronin.");
	}
	out.append("</p>\n");

	/* ---- the send ---- */

	// THE FIRST THING IN THIS REPOSITORY THAT SENDS ANYTHING. Until now the
	// page's own header said there was no send endpoint beside it and nothing
	// here that could; ar_care_send.ash is that endpoint and this is its
	// button. COwliCK asked for it, 2026-11-21: "add a 'Send # Packages'
	// button below that which sends to all selected people."
	//
	// WHAT THE BUTTON NEEDS BEFORE IT WILL LIGHT, his three conditions:
	// somebody ticked, something in the package (an item or some Meat), and a
	// note. The first is counted in the browser, so the button starts
	// disabled and ar_care.js turns it on -- which also means a page whose
	// script did not load cannot send, and that is the right way round.
	//
	// The other two are known here, and are passed as attributes rather than
	// worked out again in JavaScript: whether a package holds anything is
	// carePackageParts() and careMeat(), and neither belongs in two places.
	//
	// TWO PRESSES, NOT ONE. COwliCK's call when asked: the first press arms
	// the button and the second sends. KoL has no unsend and this mails a
	// couple of hundred people with real items in it, so one stray tap on a
	// button sitting directly under the package editor is not a thing to
	// leave possible. It is done in the page rather than with confirm(),
	// which in a WKWebView with no dialog delegate returns false at once and
	// draws nothing -- the button would simply never fire on the iPad this
	// is read on.
	boolean hasStuff = count(carePackageParts(carePackage())) > 0 || careMeat() > 0;
	boolean hasNote = careNote() != "";
	out.append("<div class='care-sendline'>");
	out.append("<button id='care-send' type='button' disabled"
		+ " data-stuff='" + (hasStuff ? "1" : "0") + "'"
		+ " data-note='" + (hasNote ? "1" : "0") + "'>");
	out.append("Send 0 Packages");
	out.append("</button>");
	// Hidden until a send is running, the same way the look-up's Stop is: a
	// Stop on screen with nothing to stop is a button that looks pressable
	// and is not.
	out.append("<button id='care-send-stop' type='button' hidden>Stop</button>");
	out.append("<span id='care-send-why' class='care-said'></span>");
	out.append("</div>\n");

	out.append("<div id='care-send-said' class='care-said'></div>\n");

	out.append("</div>\n");

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
		// SEND IS A CONTROL, not just a heading: pressing it ticks every box
		// in the column and pressing it again clears them (COwliCK,
		// 2026-11-21). Drawn as a link because there is no hover on an iPad
		// to discover it with, so it has to look pressable sitting still.
		//
		// A link rather than a <button>: it is one word in a table header,
		// and a button there would be the loudest thing on a page whose
		// actual button is the look-up.
		out.append("<tr class='care-head'><td class='care-who'>Name</td>"
			+ "<td class='care-rank'>Rank</td>"
			+ "<td class='care-seen'>Last Login</td>"
			+ "<td class='care-send'><a href='#' id='care-tick-all'"
			+ " title='tick them all, or clear them'>Send</a></td>"
			+ "<td class='care-gifts'>Packages</td></tr>");
		careRows(out, rows);
		out.append("</table>\n");
	}


	out.append(arBoxEnd() + "\n");

	out.append("</div>\n");

	// Ordered plain tags, ar_ask.js first: ar_care.js reads window.arAsk when
	// its click handler runs, and relay_Anti_Raffle.ash loads the pair the same
	// way. This page had no script at all until the look-up became a button --
	// its header used to say "a page with no controls needs no script to work",
	// which was true of it and no longer is.
	out.append(arScript("ar_ask.js"));
	out.append(arScript("ar_combo.js"));
	out.append(arScript("ar_care.js"));
	out.append("</body>\n</html>\n");
	out.write();
}
