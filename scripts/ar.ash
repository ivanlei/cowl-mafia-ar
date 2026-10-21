// ar.ash -- the gCLI side of hosting an anti-raffle.
//
//     ar, ar help            these
//     ar items               the chosen tickets
//     ar add <item>          choose one
//     ar remove <item>       unchoose one
//     ar stock               the store, source by source
//     ar restock [item]      list and park -- the one command that writes
//     ar defaultitems        replace the list with the one this ships with
//     ar count [n]           how many of each to hold
//     ar sources             where restocking may draw from
//     ar sources add <place>, ar sources remove <place>, ar sources <list>
//     ar sales [filter]      ticket sales, filtered by item or buyer
//
// Every one of these answers the same question the relay page answers, out of
// the same functions, so the two cannot disagree about what your store holds.
// See ar_core.ash.

import <ar_core.ash>
import <ar_restock.ash>

string arHelp() {
	buffer out;
	out.append("<table border=0 cellpadding=2>");
	out.append("<tr><td colspan=2><b>Hosting an anti-raffle</b></td></tr>");

	void row(string command, string what) {
		out.append("<tr><td valign=top><tt>&nbsp;ar " + command
			+ "</tt></td><td valign=top>" + what + "</td></tr>");
	}

	row("items", "the tickets you have chosen");
	row("add &lt;item&gt;", "choose one");
	row("remove &lt;item&gt;", "unchoose one");
	row("stock", "what is in the store, and what each source could supply");
	row("restock [item]", "<b>writes:</b> list the shortfall and park it");
	row("defaultitems", "replace the list with the one this ships with");
	row("count [n]", "how many of each to hold (now " + arCount() + ")");
	row("sources", "where restocking may draw from");
	row("sources add|remove &lt;place&gt;", "switch one on or off");
	row("sales [filter]", "ticket sales, by item or buyer");
	out.append("</table>");
	return out.to_string();
}

// A name, an id, or "[1234]" as KoLmafia writes them. to_item() does the fuzzy
// matching, so "pocket wish" finds the wish.
item arNamed(string what) {
	string name = what;
	while (name.starts_with(" ")) name = name.substring(1, name.length());
	while (name.ends_with(" ")) name = name.substring(0, name.length() - 1);
	if (name == "") return $item[none];

	if (name.is_integer()) return name.to_int().to_item();

	matcher bracketed = create_matcher("^\\[(\\d+)\\]", name);
	if (bracketed.find()) return bracketed.group(1).to_int().to_item();

	return name.to_item();
}

void arShowItems() {
	item [int] chosen = arTickets();
	if (count(chosen) == 0) {
		print("No tickets chosen. `ar add <item>` to choose one.", "olive");
		return;
	}

	buffer out;
	out.append("<table border=0 cellpadding=2>");
	out.append("<tr><td></td><td><b>ticket</b></td><td align=right><b>mall</b></td>"
		+ "<td align=right><b>min</b></td><td align=right><b>in store</b></td></tr>");
	foreach i, r in arRows() {
		out.append("<tr><td><img src=\"/images/itemimages/" + r.image
			+ "\" width=30 height=30></td>");
		out.append("<td>" + r.name + " <font color=gray>[id:" + r.id + "]</font></td>");
		out.append("<td align=right>" + (r.tradeable ? r.mallPrice.to_string() : "&mdash;") + "</td>");
		out.append("<td align=right>" + r.minPrice + "</td>");
		out.append("<td align=right>" + r.inStore + " of " + r.want + "</td></tr>");
	}
	out.append("</table>");
	print_html(out.to_string());
}

void arShowStock() {
	arRow [int] rows = arRows();
	if (count(rows) == 0) {
		print("No tickets chosen. `ar add <item>` to choose one.", "olive");
		return;
	}

	arLimits l = arLimitsNow();
	print("Holding " + arCount() + " of each, parked at " + arParkPrice() + ".", "blue");
	if (l.limited != "") print("Limit mode: " + l.limited + ".", "red");

	buffer out;
	out.append("<table border=0 cellpadding=2>");
	out.append("<tr><td><b>ticket</b></td><td><b>store</b></td>"
		+ "<td><b>need</b></td><td><b>can reach</b></td><td><b>where</b></td></tr>");

	foreach i, r in rows {
		string where = "";
		foreach j, s in r.sources {
			if (!s.enabled) continue;
			if (s.available < 1) continue;
			where = where + " " + s.place + "(" + s.available
				+ (s.shut == "" ? "" : ", " + s.shut) + ")";
		}
		if (where == "") where = "<font color=gray>nothing to hand</font>";

		string store = r.inStore == 0
			? "<font color=gray>none</font>"
			: r.inStore + " @ " + r.storePrice
				+ (r.storeLimit > 0 ? " limit " + r.storeLimit : "");

		out.append("<tr><td>" + r.name + "</td>");
		out.append("<td>" + store + (r.parked ? " <font color=green>parked</font>" : "") + "</td>");
		out.append("<td align=right>" + (r.shortfall > 0 ? r.shortfall.to_string() : "&mdash;") + "</td>");
		out.append("<td align=right>" + r.reachable + "</td>");
		out.append("<td>" + where + "</td></tr>");
	}
	out.append("</table>");
	print_html(out.to_string());
}

void arShowResults(arResult [int] results) {
	int changed = 0;
	foreach i, r in results {
		if (r.changed) changed = changed + 1;
		foreach j, s in r.steps {
			string line = r.name + ": " + s.what
				+ (s.place == "" ? "" : " from " + s.place)
				+ (s.amount > 0 ? " " + s.amount : "")
				+ (s.detail == "" ? "" : " -- " + s.detail);
			print(line, s.ok ? "blue" : "olive");
		}
	}
	print(changed == 0
		? "Nothing needed doing."
		: "Changed " + changed + " of " + count(results) + ".", "green");
}

// Only the chosen tickets. The rest of the store is an ordinary sale and has
// nothing to do with a raffle; mixing the two means scrolling past a week of
// spore pods to find the eleven lines you are going to read a winner out of.
void arShowSales(string filter) {
	string want = filter.to_lower_case();

	if (count(arTickets()) == 0) {
		print("No tickets chosen. `ar add <item>` to choose one.", "olive");
		return;
	}

	arSale [int] all = arSales();
	int unreadable = arUnreadable(all);
	arSale [int] sales = arTicketsAmong(all);
	if (count(sales) == 0) {
		print("Nothing in the store's sales log is one of your tickets.", "olive");
		if (unreadable > 0) {
			print(unreadable + " line(s) of the log could not be read, so they are "
				+ "not counted either.", "olive");
		}
		return;
	}

	buffer out;
	out.append("<table border=0 cellpadding=2>");
	out.append("<tr><td><b>when</b></td><td><b>buyer</b></td>"
		+ "<td align=right><b>qty</b></td><td><b>item</b></td>"
		+ "<td align=right><b>meat</b></td></tr>");

	int shown = 0;
	foreach i, s in sales {
		if (want != "" && !s.buyer.to_lower_case().contains_text(want)
			&& !s.name.to_lower_case().contains_text(want)) continue;

		out.append("<tr><td>" + s.stamp + "</td><td>" + s.buyer + "</td>");
		out.append("<td align=right>" + s.qty + "</td><td>" + s.name + "</td>");
		out.append("<td align=right>" + s.meat + "</td></tr>");
		shown = shown + 1;
	}
	out.append("</table>");

	if (shown == 0) {
		print("No ticket sale matches \"" + filter + "\".", "olive");
		return;
	}
	print_html(out.to_string());
	if (unreadable > 0) {
		print(unreadable + " line(s) of the log could not be read and are not "
			+ "shown; one of them could be a ticket.", "olive");
	}
}

// One function per command, rather than the bodies inline in the switch
// below. A switch's cases share one scope in ASH, so every local would have to
// have a name no other case had used, and the first time two of them wanted a
// variable called "it" the compiler would be right and unhelpful about it.

void arDoAdd(string rest) {
	item adding = arNamed(rest);
	if (adding == $item[none]) {
		print("No item called \"" + rest + "\".", "red");
		return;
	}
	if (!arAddTicket(adding)) {
		print(adding + " is already a ticket.", "olive");
		return;
	}
	print("Added " + adding + " [id:" + adding.to_int() + "].", "green");
}

void arDoRemove(string rest) {
	item dropping = arNamed(rest);
	if (dropping == $item[none]) {
		print("No item called \"" + rest + "\".", "red");
		return;
	}
	if (!arRemoveTicket(dropping)) {
		print(dropping + " is not a ticket.", "olive");
		return;
	}
	print("Removed " + dropping + ".", "green");
}

// The shipped list, for somebody who has already chosen tickets and wants to
// start from it anyway. The list it replaces is printed before it goes, so a
// mistake is one `set arTicketItems=...` away from undone rather than gone.
void arDoDefaultItems() {
	item [int] had = arTickets();
	string before = get_property(AR_ITEMS);

	string [int] ids = arDefaultTicketIds();
	set_property(AR_ITEMS, arJoin(ids, ","));

	if (count(had) > 0) {
		print("Replaced " + count(had) + " ticket(s). To put them back:", "olive");
		print("  set " + AR_ITEMS + "=" + before, "olive");
	}
	print("Now holding " + count(arTickets()) + " tickets from the shipped list.", "green");
}

void arDoCount(string rest) {
	if (rest == "") {
		print("Holding " + arCount() + " of each.", "blue");
		return;
	}
	if (!rest.is_integer() || rest.to_int() < 1) {
		print("\"" + rest + "\" is not a number of tickets.", "red");
		return;
	}
	set_property(AR_COUNT, rest.to_int().to_string());
	print("Holding " + arCount() + " of each.", "green");
}

// `ar sources` on its own lists them; `add` and `remove` turn one on or off;
// a bare list sets them all at once.
//
// Naming one to switch off is the one people reach for, and setting the whole
// list was the only way to do it -- which meant removing the closet was
// "ar sources inventory display storage", a sentence you have to compose out
// of what you did not want to say.
void arSourceList(string said) {
	boolean [string] on = arSources();
	string [int] listed;
	string [int] off;
	foreach i, place in arAllSources() {
		if (on contains place) listed[count(listed)] = place;
		else off[count(off)] = place;
	}
	print(said + ": " + (count(listed) == 0 ? "nothing" : arJoin(listed, ", ")) + ".",
		count(listed) == 0 ? "red" : "blue");
	if (count(off) > 0) print("Off: " + arJoin(off, ", ") + ".", "gray");
}

void arWriteSources(boolean [string] on) {
	string [int] keep;
	foreach i, place in arAllSources() {
		if (on contains place) keep[count(keep)] = place;
	}
	set_property(AR_SOURCES, arJoin(keep, ","));
}

void arDoSources(string rest) {
	if (rest == "") {
		arSourceList("Drawing from");
		return;
	}

	// Commas or spaces, since both read naturally on a command line.
	string commas = rest.replace_string(" ", ",");
	string [int] pieces = commas.split_string(",");

	string [int] words;
	foreach i, piece in pieces {
		if (piece == "") continue;
		words[count(words)] = piece.to_lower_case();
	}
	if (count(words) == 0) {
		print("Name at least one of: " + arJoin(arAllSources(), ", ") + ".", "red");
		return;
	}

	string verb = words[0];
	boolean adding = verb == "add" || verb == "on";
	boolean dropping = verb == "remove" || verb == "off" || verb == "drop";

	if (adding || dropping) {
		if (count(words) < 2) {
			print("Which one? " + arJoin(arAllSources(), ", ") + ".", "red");
			return;
		}
		boolean [string] on = arSources();
		for i from 1 to count(words) - 1 {
			string place = words[i];
			if (!arIsSource(place)) {
				print("\"" + place + "\" is not one of: "
					+ arJoin(arAllSources(), ", ") + ".", "red");
				return;
			}
			if (adding) on[place] = true;
			else remove on[place];
		}
		// Restocking with nothing switched on would do nothing and say
		// nothing, which reads as a broken restock rather than as a setting.
		if (count(on) == 0) {
			print("That would leave nothing to draw from.", "red");
			return;
		}
		arWriteSources(on);
		arSourceList("Drawing from");
		return;
	}

	boolean [string] asked;
	foreach i, place in words {
		if (!arIsSource(place)) {
			print("\"" + place + "\" is not one of: "
				+ arJoin(arAllSources(), ", ") + ".", "red");
			return;
		}
		asked[place] = true;
	}
	arWriteSources(asked);
	arSourceList("Drawing from");
}

void arDoRestock(string rest) {
	if (count(arTickets()) == 0) {
		print("No tickets chosen. `ar add <item>` to choose one.", "olive");
		return;
	}
	if (rest == "") {
		arShowResults(arRestockAll());
		return;
	}

	item one = arNamed(rest);
	if (one == $item[none]) {
		print("No item called \"" + rest + "\".", "red");
		return;
	}
	if (!arHasTicket(one)) {
		print(one + " is not a ticket. `ar add " + one + "` first.", "red");
		return;
	}

	item [int] just;
	just[0] = one;
	arShowResults(arRestock(just));
}

// Varargs, so that a bare `ar` is a legal call.
//
// `void main(string args)` looks equivalent and is not: run with no arguments,
// KoLmafia has no value for the parameter and asks for one with a modal Swing
// dialog (AshRuntime, DataTypes.promptForValue). The command thread blocks on
// that dialog, and every gCLI command behind it queues up waiting -- which is
// what bare `ar` did on 2026-10-21. A relay script is already spared this,
// since asking would hang the page, but a gCLI one is not.
void main(string ... words) {
	string command = "";
	string rest = "";

	foreach i, word in words {
		if (i == 0) {
			command = word;
			continue;
		}
		rest = rest == "" ? word : rest + " " + word;
	}

	// KoLmafia splits on spaces, but a quoted or single-argument call arrives
	// whole -- so the first word of the first word is still the command.
	int space = command.index_of(" ");
	if (space > 0) {
		string first = command.substring(0, space);
		string tail = command.substring(space + 1, command.length());
		command = first;
		rest = rest == "" ? tail : tail + " " + rest;
	}

	while (rest.starts_with(" ")) rest = rest.substring(1, rest.length());
	command = command.to_lower_case();

	switch (command) {
		// Bare `ar` is `ar help`. It used to print the tickets and the store,
		// which meant the one thing you type when you do not know what to type
		// answered with two tables and no list of commands.
		case "":
		case "help":
			print_html(arHelp());
			return;

		case "items":
			arShowItems();
			return;

		case "add":
			arDoAdd(rest);
			return;

		case "remove":
			arDoRemove(rest);
			return;

		case "stock":
			arShowStock();
			return;

		case "defaultitems":
			arDoDefaultItems();
			return;

		case "count":
			arDoCount(rest);
			return;

		case "sources":
			arDoSources(rest);
			return;

		case "restock":
			arDoRestock(rest);
			return;

		case "sales":
			arShowSales(rest);
			return;
	}

	print("Don't know \"" + command + "\".", "red");
	print_html(arHelp());
}
