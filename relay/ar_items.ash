// ar_items.ash -- choosing the tickets.
//
//     ?q=<text>        search every item by name
//     ?add=<id>        choose one
//     ?remove=<id>     unchoose one
//     ?defaults=1      replace the list with the one this ships with
//     (none of them)   the chosen list
//
// The search runs here rather than in the browser. `$items[]` with nothing in
// the brackets is an implicit enumeration of every item KoLmafia knows
// (Parser.parseTypedConstant falls through to type.allValues()), so matching
// happens against the real list, server-side -- rather than shipping thirty
// thousand names to an iPad once per page load and keeping them in step
// afterwards.

import <ar_relay.ash>

// Enough to be worth running, few enough to read. A search matching half the
// game is a search that wants another word, and saying so is better than
// scrolling.
int AR_SEARCH_MIN = 3;
int AR_SEARCH_MAX = 40;

void arSearch(string q) {
	string want = q.to_lower_case();

	// Two passes rather than a sort: a name that starts with what you typed is
	// almost always the one you meant, and ASH has no comparator to say so.
	item [int] starts;
	item [int] inside;
	foreach it in $items[] {
		string name = it.to_string().to_lower_case();
		if (name.starts_with(want)) {
			starts[count(starts)] = it;
			continue;
		}
		if (name.contains_text(want)) inside[count(inside)] = it;
	}

	int total = count(starts) + count(inside);

	buffer out;
	out.append("{\"ok\":true,\"error\":\"\",\"total\":" + total + ",\"found\":[");
	int written = 0;

	void emit(item it) {
		if (written >= AR_SEARCH_MAX) return;
		if (written > 0) out.append(",");
		out.append("{\"id\":" + it.to_int());
		out.append(",\"name\":" + arQuoted(it.to_string()));
		out.append(",\"image\":" + arQuoted(it.image));
		out.append(",\"tradeable\":" + (it.is_tradeable() ? "true" : "false"));
		out.append(",\"minPrice\":" + arMinPrice(it));
		out.append(",\"chosen\":" + (arHasTicket(it) ? "true" : "false") + "}");
		written = written + 1;
	}

	foreach i, it in starts emit(it);
	foreach i, it in inside emit(it);

	out.append("],\"shown\":" + written + "}");
	out.write();
}

void arChosen() {
	buffer out;
	out.append("{\"ok\":true,\"error\":\"\",\"settings\":" + arSettingsJson() + ",\"items\":[");
	foreach i, r in arRows() {
		if (i > 0) out.append(",");
		out.append(arRowJson(r));
	}
	out.append("]}");
	out.write();
}

void main() {
	if (!arAuthorised()) {
		arRefuseStale();
		return;
	}

	// Explicit, like the restock, and for the same reason: it throws away a
	// list you may have spent a while building, so it does not happen because
	// a page was opened.
	if (form_field("defaults") == "1") {
		set_property(AR_ITEMS, arJoin(arDefaultTicketIds(), ","));
		arChosen();
		return;
	}

	string adding = form_field("add");
	string removing = form_field("remove");
	string q = form_field("q");

	if (adding != "") {
		if (!adding.is_integer()) {
			arRefuse("Not an item id.");
			return;
		}
		item it = adding.to_int().to_item();
		if (it == $item[none]) {
			arRefuse("No item with that id.");
			return;
		}
		arAddTicket(it);
		arChosen();
		return;
	}

	if (removing != "") {
		if (!removing.is_integer()) {
			arRefuse("Not an item id.");
			return;
		}
		item it = removing.to_int().to_item();
		if (it == $item[none]) {
			arRefuse("No item with that id.");
			return;
		}
		arRemoveTicket(it);
		arChosen();
		return;
	}

	if (q != "") {
		if (q.length() < AR_SEARCH_MIN) {
			arRefuse("Type at least " + AR_SEARCH_MIN + " letters.");
			return;
		}
		arSearch(q);
		return;
	}

	arChosen();
}
