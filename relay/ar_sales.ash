// ar_sales.ash -- what has sold, of the items you use as tickets.
//
// Only those. The rest of the store is an ordinary sale and has nothing to do
// with a raffle; mixing the two means scrolling past a week of whatever else
// you sell to find the eleven lines you read a winner out of.
//
// Filtering by item and by buyer happens in the browser, over the whole log,
// because the lists to filter by are built out of the log itself: asking the
// server again per keystroke would be asking it to re-fetch the store.
//
// The log is KoL's, fetched by get_shop_log() through a ManageStoreRequest, so
// it is as long as KoL is willing to make it and not something this keeps.

import <ar_relay.ash>

void main() {
	if (!arAuthorised()) {
		arRefuseStale();
		return;
	}

	// One read of the store log, filtered two ways: get_shop_log() is a round
	// trip to KoL, and this used to make two of them.
	arSale [int] all = arSales();
	arSale [int] sales = arTicketsAmong(all);
	int unreadable = arUnreadable(all);

	// The two filter lists, built from what is actually there. A buyer who
	// bought twice appears once; an item nobody bought does not appear at all.
	boolean [string] buyers;
	boolean [string] names;
	foreach i, s in sales {
		buyers[s.buyer] = true;
		names[s.name] = true;
	}

	buffer out;
	out.append("{\"ok\":true,\"error\":\"\"");
	out.append(",\"tickets\":" + count(arTickets()));
	out.append(",\"unreadable\":" + unreadable);

	out.append(",\"buyers\":[");
	int n = 0;
	// One variable, not two: a boolean map iterated with two hands back the
	// boolean, which is "true" for every key and sorts no better for it.
	foreach who in buyers {
		if (n > 0) out.append(",");
		out.append(arQuoted(who));
		n = n + 1;
	}
	out.append("],\"names\":[");
	n = 0;
	foreach what in names {
		if (n > 0) out.append(",");
		out.append(arQuoted(what));
		n = n + 1;
	}

	out.append("],\"sales\":[");
	foreach i, s in sales {
		if (i > 0) out.append(",");
		out.append(arSaleJson(s));
	}
	out.append("]}");
	out.write();
}
