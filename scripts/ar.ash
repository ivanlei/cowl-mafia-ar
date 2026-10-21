// ar.ash -- the gCLI side of hosting an anti-raffle.
//
//     ar                     what you have chosen, and what is in the store
//     ar items               the chosen tickets
//     ar add <item>          choose one
//     ar remove <item>       unchoose one
//     ar stock               the store, source by source
//     ar restock [item]      list and park -- the one command that writes
//     ar count [n]           how many of each to hold
//     ar sources [list]      where restocking may draw from
//     ar sales [filter]      what has sold, filtered by item or buyer
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
	row("count [n]", "how many of each to hold (now " + arCount() + ")");
	row("sources [list]", "where restocking may draw from");
	row("sales [filter]", "what has sold, by item or buyer");
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
		out.append("<td>" + r.name + " <font color=gray>[" + r.id + "]</font></td>");
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
			if (s.place == "mall") {
				if (s.shut != "") { where = where + " mall(" + s.shut + ")"; continue; }
				where = where + " mall(" + s.price + ")";
				continue;
			}
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

void arShowSales(string filter) {
	string want = filter.to_lower_case();
	arSale [int] sales = arSales();
	if (count(sales) == 0) {
		print("Nothing in the store's sales log.", "olive");
		return;
	}

	buffer out;
	out.append("<table border=0 cellpadding=2>");
	out.append("<tr><td><b>when</b></td><td><b>buyer</b></td>"
		+ "<td align=right><b>qty</b></td><td><b>item</b></td>"
		+ "<td align=right><b>meat</b></td></tr>");

	int shown = 0;
	foreach i, s in sales {
		if (!s.parsed) {
			if (want != "") continue;
			out.append("<tr><td colspan=5><font color=gray>" + s.raw + "</font></td></tr>");
			shown = shown + 1;
			continue;
		}
		if (want != "" && !s.buyer.to_lower_case().contains_text(want)
			&& !s.name.to_lower_case().contains_text(want)) continue;

		out.append("<tr><td>" + s.stamp + "</td><td>" + s.buyer + "</td>");
		out.append("<td align=right>" + s.qty + "</td><td>" + s.name + "</td>");
		out.append("<td align=right>" + s.meat + "</td></tr>");
		shown = shown + 1;
	}
	out.append("</table>");

	if (shown == 0) {
		print("Nothing in the sales log matches \"" + filter + "\".", "olive");
		return;
	}
	print_html(out.to_string());
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
	print("Added " + adding + " [" + adding.to_int() + "].", "green");
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

void arDoSources(string rest) {
	if (rest == "") {
		boolean [string] on = arSources();
		string [int] listed;
		foreach i, place in arAllSources() {
			if (on contains place) listed[count(listed)] = place;
		}
		print("Drawing from: "
			+ (count(listed) == 0 ? "nothing" : arJoin(listed, ", ")) + ".", "blue");
		print("Known sources: " + arJoin(arAllSources(), ", ") + ".", "gray");
		return;
	}

	// Commas or spaces, since both read naturally on a command line.
	string commas = rest.replace_string(" ", ",");
	string [int] pieces = commas.split_string(",");
	string [int] asked;
	foreach i, piece in pieces {
		if (piece == "") continue;
		string place = piece.to_lower_case();
		if (!arIsSource(place)) {
			print("\"" + piece + "\" is not one of: "
				+ arJoin(arAllSources(), ", ") + ".", "red");
			return;
		}
		asked[count(asked)] = place;
	}
	if (count(asked) == 0) {
		print("Name at least one of: " + arJoin(arAllSources(), ", ") + ".", "red");
		return;
	}
	set_property(AR_SOURCES, arJoin(asked, ","));
	print("Drawing from: " + arJoin(asked, ", ") + ".", "green");
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

void main(string args) {
	string line = args;
	while (line.starts_with(" ")) line = line.substring(1, line.length());

	string command = line;
	string rest = "";
	int space = line.index_of(" ");
	if (space > 0) {
		command = line.substring(0, space);
		rest = line.substring(space + 1, line.length());
		while (rest.starts_with(" ")) rest = rest.substring(1, rest.length());
	}
	command = command.to_lower_case();

	switch (command) {
		case "":
			arShowItems();
			arShowStock();
			return;

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
