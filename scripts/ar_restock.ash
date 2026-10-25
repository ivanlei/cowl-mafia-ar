// ar_restock.ash -- getting the tickets into the store and parked there.
//
// The only file in this repository that changes anything. Everything else
// reads: what you have chosen, what is in the store, what has sold. Keeping
// the one that writes in a file of its own means a page that only wants to
// show you a table cannot reach the code that lists items for sale, and a
// reader of this repository can see at a glance which half is which.
//
// What restocking does, per ticket, and only as much of it as is needed:
//
//   1. gather the shortfall into inventory from the sources you have switched
//      on, nearest first;
//   2. list whatever is missing from the store;
//   3. if it is listed at some other price, move it to the parking price.
//
// A row already parked correctly is left alone and says so. Nothing is ever
// bought: every source moves something you already own from one place you own
// to another, so hosting a raffle costs tickets and no meat.
//
// Parking, not pricing: between raffles the tickets sit at a price nobody can
// pay, so announcing one is a single price change rather than a scramble to
// list a dozen items while /games waits.

import <ar_core.ash>

// What one ticket's restock did, as a line per thing attempted. The page and
// the gCLI both show these; neither invents its own wording.
record arStep {
	string what;        // "gather", "list", "reprice", "skip"
	string place;       // which source, for a gather
	int amount;
	boolean ok;
	string detail;
};

record arResult {
	item it;
	string name;
	boolean changed;
	arStep [int] steps;
};

void arNote(arResult r, string what, string place, int amount, boolean ok, string detail) {
	arStep s;
	s.what = what;
	s.place = place;
	s.amount = amount;
	s.ok = ok;
	s.detail = detail;
	r.steps[count(r.steps)] = s;
	if (ok && amount > 0) r.changed = true;
}

// Take as many as are wanted out of one place. Returns how many arrived.
//
// Nothing is put back afterwards and nothing is tidied: where a thing lives
// between raffles is Philter's business, and it will file the leftovers away
// on its next run.
int arGatherFrom(item it, int wanted, string place, arLimits l, arResult r) {
	if (wanted < 1) return 0;

	// Already in hand is not a fetch; it is the starting point.
	if (place == "inventory") return 0;

	string shut = arShutBecause(place, l);

	int available = arAvailable(it, place);
	if (available < 1) return 0;

	if (shut != "") {
		arNote(r, "skip", place, 0, false,
			available + " there, but " + shut);
		return 0;
	}

	int taking = min(wanted, available);
	boolean took = false;
	switch (place) {
		case "closet": took = take_closet(taking, it); break;
		case "display": took = take_display(taking, it); break;
		case "storage": took = take_storage(taking, it); break;
	}

	if (!took) {
		arNote(r, "skip", place, 0, false, "could not take " + taking + " out");
		return 0;
	}
	arNote(r, "gather", place, taking, true, "");
	return taking;
}

arResult arRestockOne(item it, arLimits l) {
	arResult r;
	r.it = it;
	r.name = arItemName(it);
	r.changed = false;

	int want = arCount();
	int park = arParkPrice();

	int inStore = it.shop_amount();
	// 0 rather than what shop_price() says about an item that is not in the
	// store, which is MALL_MAX -- the same number the parking price defaults
	// to. See arRowFor() in ar_core.ash.
	int price = inStore > 0 ? it.shop_price() : 0;

	int limit = inStore > 0 ? it.shop_limit() : 0;

	// Already right. Said out loud rather than passed over in silence, so that
	// a restock which did nothing reads as a restock which did not need to.
	// The limit counts as part of being right: a listing made before tickets
	// carried one is at the parking price already, and would never be touched
	// again if only the price were checked.
	if (inStore >= want && price == park && limit == AR_TICKET_LIMIT) {
		arNote(r, "skip", "", 0, true, "already " + inStore + " parked at " + park
			+ ", limit " + limit);
		return r;
	}

	int missing = want - inStore;
	if (missing > 0) {
		int have = arInHand(it);
		boolean [string] on = arSources();

		// Nearest first: what is in hand, then the two that cost nothing,
		// then a Ronin pull. arAllSources() holds that order.
		foreach i, place in arAllSources() {
			if (have >= missing) break;
			if (!(on contains place)) continue;
			have = have + arGatherFrom(it, missing - have, place, l, r);
		}

		int listing = min(missing, have);
		if (listing > 0) {
			// put_shop() prices and limits in the same call, so the ticket
			// gets its one-per-person limit as it goes in rather than at the
			// moment a raffle opens. See AR_TICKET_LIMIT.
			boolean put = put_shop(park, AR_TICKET_LIMIT, listing, it);
			arNote(r, "list", "", listing, put,
				put ? "at " + park + ", limit " + AR_TICKET_LIMIT : "put_shop refused");
			if (put) inStore = inStore + listing;
		}
		if (have < missing) {
			arNote(r, "skip", "", 0, false,
				"short by " + (missing - have) + " of " + want);
		}
	}

	// Whatever is in there now, at the parking price and the ticket limit.
	// Done after listing, so an item that was already in the store wrong gets
	// moved once rather than twice.
	//
	// The limit is in the test as well as the call because reprice_shop() sets
	// both: passing the limit it already has would be a no-op, but passing the
	// one it should have is how a listing from before this gets fixed. The
	// two-argument reprice_shop() keeps the existing limit instead, which is
	// exactly what must not happen here.
	if (inStore > 0 && (it.shop_price() != park || it.shop_limit() != AR_TICKET_LIMIT)) {
		boolean moved = reprice_shop(park, AR_TICKET_LIMIT, it);
		arNote(r, "reprice", "", inStore, moved,
			moved ? "to " + park + ", limit " + AR_TICKET_LIMIT : "reprice_shop refused");
	}

	return r;
}

arResult [int] arRestock(item [int] which) {
	arLimits l = arLimitsNow();
	arResult [int] results;
	foreach i, it in which results[count(results)] = arRestockOne(it, l);
	return results;
}

arResult [int] arRestockAll() {
	return arRestock(arTickets());
}
