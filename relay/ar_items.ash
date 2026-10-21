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

// Everything you hold that could go in the store, from the four places
// restocking draws from, each with how many are there and where. Counted
// across all of them, since the same item in the closet and in Hagnk's is one
// entry in a dropdown and not two.
//
// Tradeable only. is_tradeable() is the flag that decides it -- KoL's own t=1
// on an inventory row, and the test KoLmafia itself applies before putting
// anything in a store (StoreManager, "if (!ItemDatabase.isTradeable(itemId))
// continue"). An untradeable item cannot be listed and could not be given to
// a winner either, so it is not a ticket in any sense.
//
// Read fresh on every call. get_inventory(), get_closet(), get_display() and
// get_storage() each walk KoLConstants' live list -- there is no cache here
// and no stored copy of the answer -- so the dropdown is whatever KoLmafia
// believes you hold at the moment you open the tab. It is KoLmafia's belief,
// updated as it parses what KoL tells it, rather than a fresh ask of KoL.
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

	// Once, not once per held item: arHasTicket() re-reads the preference on
	// every call, and there are a couple of thousand items to ask about.
	boolean [item] chosen = arTicketSet();

	buffer out;
	out.append("{\"ok\":true,\"error\":\"\",\"held\":[");
	int written = 0;
	foreach it, n in total {
		// Already a ticket is already answered; offering it again is offering
		// a choice that does nothing.
		if (chosen contains it) continue;
		if (!it.is_tradeable()) continue;
		if (written > 0) out.append(",");
		out.append("{\"id\":" + it.to_int());
		out.append(",\"name\":" + arQuoted(arItemName(it)));
		out.append(",\"have\":" + n);
		out.append(",\"places\":" + arQuoted(places[it]) + "}");
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
