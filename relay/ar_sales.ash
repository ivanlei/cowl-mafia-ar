// ar_sales.ash -- what has sold out of the store.
//
//     ?tickets=1   only the chosen tickets
//     (otherwise)  everything the store's log holds
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

	boolean ticketsOnly = form_field("tickets") == "1";
	arSale [int] sales = ticketsOnly ? arTicketSales() : arSales();

	// The two filter lists, built from what is actually there. A buyer who
	// bought twice appears once; an item nobody bought does not appear at all.
	boolean [string] buyers;
	boolean [string] names;
	int unparsed = 0;
	foreach i, s in sales {
		if (!s.parsed) {
			unparsed = unparsed + 1;
			continue;
		}
		buyers[s.buyer] = true;
		names[s.name] = true;
	}

	buffer out;
	out.append("{\"ok\":true,\"error\":\"\"");
	out.append(",\"ticketsOnly\":" + (ticketsOnly ? "true" : "false"));
	out.append(",\"unparsed\":" + unparsed);

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
