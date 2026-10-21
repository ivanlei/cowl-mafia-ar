// ar_items.ash -- choosing the tickets.
//
//     ?have=1          every item you hold, for the dropdown
//     ?add=<id>        choose one
//     ?remove=<id>     unchoose one
//     ?defaults=1      replace the list with the one this ships with
//     (none of them)   the chosen list
//
// The dropdown offers what you hold rather than every item in the game. A
// ticket is something you are going to put in your store, so the useful list
// is the one restocking could actually reach -- and a list of thirty thousand
// items, nearly all of which you own none of, is a list you have to know the
// answer before you can use.
//
// Whole-game search lives on in `ar add <item>` at the gCLI, which takes a
// name or an id and does not care whether you hold one yet.

import <ar_relay.ash>

// Everything in the four places restocking draws from, each with how many are
// there and where. Counted across all of them, since the same item in the
// closet and in Hagnk's is one entry in a dropdown and not two.
//
// Not sorted here: the page sorts it with localeCompare, which knows about
// accents and case in a way ASH's sort does not, and already does the same
// for the sales filters.
void arHeld() {
	int [item] total;
	string [item] places;

	void gather(int [item] held, string place) {
		foreach it, n in held {
			if (n < 1) continue;
			total[it] = total[it] + n;
			places[it] = places[it] == "" ? place : places[it] + ", " + place;
		}
	}

	gather(get_inventory(), "inventory");
	gather(get_closet(), "closet");
	gather(get_display(), "display");
	gather(get_storage(), "storage");

	buffer out;
	out.append("{\"ok\":true,\"error\":\"\",\"held\":[");
	int written = 0;
	foreach it, n in total {
		// Already a ticket is already answered; offering it again is offering
		// a choice that does nothing.
		if (arHasTicket(it)) continue;
		if (written > 0) out.append(",");
		out.append("{\"id\":" + it.to_int());
		out.append(",\"name\":" + arQuoted(arItemName(it)));
		out.append(",\"have\":" + n);
		out.append(",\"places\":" + arQuoted(places[it]));
		out.append(",\"tradeable\":" + (it.is_tradeable() ? "true" : "false") + "}");
		written = written + 1;
	}
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

	if (form_field("have") == "1") {
		arHeld();
		return;
	}

	arChosen();
}
