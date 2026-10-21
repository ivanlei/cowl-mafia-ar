// ar_relay.ash -- what the four endpoints share: the password check, the shape
// of an answer, and the JSON for the three things the page draws.
//
// Every endpoint answers {"ok":..,"error":".."} and then whatever it is for,
// so the page has one way of telling a refusal from an answer and never has to
// guess from an HTTP status. A stale password hash is the exception it cannot
// see: KoLmafia answers that with an empty 401 before a relay script runs at
// all (RelayAgent), which the page reads as "reload me".

import <ar_core.ash>

boolean arAuthorised() {
	return form_field("pwd") == my_hash();
}

// Every error here is one of this repository's own sentences and never echoes
// back what the browser sent, so there is nothing in one that needs escaping.
void arRefuse(string why) {
	write("{\"ok\":false,\"error\":\"" + why + "\"}");
}

void arRefuseStale() {
	arRefuse("This page is out of date. Reload it.");
}

string arSourceJson(arSource s) {
	buffer out;
	out.append("{\"place\":" + arQuoted(s.place));
	out.append(",\"available\":" + s.available);
	out.append(",\"enabled\":" + (s.enabled ? "true" : "false"));
	out.append(",\"shut\":" + arQuoted(s.shut) + "}");
	return out.to_string();
}

string arRowJson(arRow r) {
	buffer out;
	out.append("{\"id\":" + r.id);
	out.append(",\"name\":" + arQuoted(r.name));
	out.append(",\"image\":" + arQuoted(r.image));
	out.append(",\"inStore\":" + r.inStore);
	out.append(",\"storePrice\":" + r.storePrice);
	out.append(",\"storeLimit\":" + r.storeLimit);
	out.append(",\"parked\":" + (r.parked ? "true" : "false"));
	out.append(",\"want\":" + r.want);
	out.append(",\"shortfall\":" + r.shortfall);
	out.append(",\"reachable\":" + r.reachable);
	out.append(",\"mallPrice\":" + r.mallPrice);
	out.append(",\"minPrice\":" + r.minPrice);
	out.append(",\"tradeable\":" + (r.tradeable ? "true" : "false"));
	out.append(",\"sources\":[");
	foreach i, s in r.sources {
		if (i > 0) out.append(",");
		out.append(arSourceJson(s));
	}
	out.append("]}");
	return out.to_string();
}

string arSaleJson(arSale s) {
	buffer out;
	out.append("{\"id\":" + s.id);
	out.append(",\"parsed\":" + (s.parsed ? "true" : "false"));
	out.append(",\"stamp\":" + arQuoted(s.stamp));
	out.append(",\"date\":" + arQuoted(s.date));
	out.append(",\"time\":" + arQuoted(s.time));
	out.append(",\"buyer\":" + arQuoted(s.buyer));
	out.append(",\"qty\":" + s.qty);
	out.append(",\"name\":" + arQuoted(s.name));
	out.append(",\"itemId\":" + s.it.to_int());
	out.append(",\"image\":" + arQuoted(s.it == $item[none] ? "" : s.it.image));
	out.append(",\"meat\":" + s.meat);
	out.append(",\"raw\":" + arQuoted(s.raw) + "}");
	return out.to_string();
}

// The settings every tab shows in its header, so a page that has just changed
// one does not have to ask again to redraw the rest.
string arSettingsJson() {
	arLimits l = arLimitsNow();
	boolean [string] on = arSources();

	buffer out;
	out.append("{\"count\":" + arCount());
	out.append(",\"parkPrice\":" + arParkPrice());
	out.append(",\"parkMax\":" + AR_MALL_MAX);
	out.append(",\"pulls\":" + l.pulls);
	out.append(",\"caseOpen\":" + (l.caseOpen ? "true" : "false"));
	out.append(",\"limited\":" + arQuoted(l.limited));
	out.append(",\"sources\":[");
	foreach i, place in arAllSources() {
		if (i > 0) out.append(",");
		out.append("{\"place\":" + arQuoted(place)
			+ ",\"enabled\":" + ((on contains place) ? "true" : "false") + "}");
	}
	out.append("]}");
	return out.to_string();
}
