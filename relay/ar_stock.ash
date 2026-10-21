// ar_stock.ash -- the one endpoint that changes anything.
//
//     ?restock=1            every chosen ticket
//     ?restock=1&item=<id>  just that one
//
// Nothing happens without restock=1, so opening this page reads as a refusal
// rather than as a restock: the read-only view of the same rows is in
// ar_items.ash, and this one has to be asked on purpose.
//
// The answer carries both what was done and the rows as they stand afterwards,
// so the page redraws from what KoLmafia now believes rather than from what
// the browser thought it asked for.

import <ar_relay.ash>
import <ar_restock.ash>

string arStepJson(arStep s) {
	buffer out;
	out.append("{\"what\":" + arQuoted(s.what));
	out.append(",\"place\":" + arQuoted(s.place));
	out.append(",\"amount\":" + s.amount);
	out.append(",\"ok\":" + (s.ok ? "true" : "false"));
	out.append(",\"detail\":" + arQuoted(s.detail) + "}");
	return out.to_string();
}

string arResultJson(arResult r) {
	buffer out;
	out.append("{\"id\":" + r.it.to_int());
	out.append(",\"name\":" + arQuoted(r.name));
	out.append(",\"changed\":" + (r.changed ? "true" : "false"));
	out.append(",\"steps\":[");
	foreach i, s in r.steps {
		if (i > 0) out.append(",");
		out.append(arStepJson(s));
	}
	out.append("]}");
	return out.to_string();
}

void arAnswer(arResult [int] results) {
	buffer out;
	out.append("{\"ok\":true,\"error\":\"\",\"settings\":" + arSettingsJson());
	out.append(",\"results\":[");
	foreach i, r in results {
		if (i > 0) out.append(",");
		out.append(arResultJson(r));
	}
	out.append("],\"items\":[");
	// Read after the fact, not predicted: a reprice that KoL refused should
	// show the price KoL still has.
	foreach i, row in arRows() {
		if (i > 0) out.append(",");
		out.append(arRowJson(row));
	}
	out.append("]}");
	out.write();
}

void main() {
	if (!arAuthorised()) {
		arRefuseStale();
		return;
	}

	if (form_field("restock") != "1") {
		arRefuse("Nothing asked for.");
		return;
	}

	if (count(arTickets()) == 0) {
		arRefuse("No tickets chosen yet.");
		return;
	}

	string one = form_field("item");
	if (one == "") {
		arAnswer(arRestockAll());
		return;
	}

	if (!one.is_integer()) {
		arRefuse("Not an item id.");
		return;
	}
	item it = one.to_int().to_item();
	if (it == $item[none] || !arHasTicket(it)) {
		arRefuse("That is not one of your tickets.");
		return;
	}

	item [int] just;
	just[0] = it;
	arAnswer(arRestock(just));
}
