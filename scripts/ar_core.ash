// ar_core.ash -- hosting an anti-raffle: the chosen tickets, what is in the
// store, and what has sold. Everything the gCLI command and the relay page
// both need, so the two cannot drift apart.
//
// An anti-raffle is a game you host. You put a number of a good item in your
// store at or near its minimum price with a per-person limit, announce it in
// /games, and when the tickets have sold you have a bot roll 1d<tickets> and
// read the winning line out of your store's sales log. The wiki's Antiraffle
// page is the rules; this is the bookkeeping either side of them.
//
// This file lives in scripts/ and is imported from relay/ as well. KoLmafia's
// import search (KoLmafiaCLI.findScriptFile) walks the root, scripts/,
// planting/ and relay/ and takes the one match -- which is also why every file
// in this repository is "ar"-prefixed. Two files of the same name anywhere in
// a KoLmafia installation is not a shadowing, it is a hard "too many matches"
// error, and another project installs into these same two folders.
//
// Nothing here writes to the store. The restocking half is ar_restock.ash,
// kept separate so that reading what you have can never be the thing that
// changes it.

// --- Preferences -----------------------------------------------------------
//
// Named, not typed inline, because the gCLI command, four relay endpoints and
// the settings allowlist all have to agree about the spelling.

string AR_ITEMS = "arTicketItems";
string AR_COUNT = "arRestockCount";
string AR_PARK = "arParkPrice";
string AR_SOURCES = "arSources";
string AR_PRICE_LEVEL = "arPriceLevel";
string AR_MAX_PRICE = "arMaxPrice";

// StoreManager.MALL_MAX. Twelve digits, not the nine it looks like it should
// be, and the number KoL itself refuses to go above.
int AR_MALL_MAX = 999999999999;

int AR_COUNT_DEFAULT = 11;

// Eleven tickets is the common number, and ten is the other one. Nothing here
// enforces either: the wiki says to use more when /games is busy.

// --- The chosen tickets ----------------------------------------------------
//
// Stored as item ids. Not names: an item name can contain a comma (which is
// the separator) and an apostrophe and a trademark entity, names are what KoL
// changes when it renames something, and the id is already the id. Names are
// rendered everywhere and stored nowhere.

// Join a list of strings.
//
// Not join_strings(), which wants an ASH *array* -- AggregateType(STRING, 0)
// -- and every list built a piece at a time here is a map. `string [int] x`
// is a TreeMap; only `string [5] x` is an array, and a list whose length is
// not known when it is declared cannot be one. Handing a map to
// join_strings() is not a type error at parse time; it is a
// ClassCastException at run time, which in a relay script means the page gets
// a bare 404 and the reason goes to the gCLI and nowhere else.
string arJoin(string [int] parts, string separator) {
	buffer out;
	int written = 0;
	foreach i, piece in parts {
		if (written > 0) out.append(separator);
		out.append(piece);
		written = written + 1;
	}
	return out.to_string();
}

item [int] arTickets() {
	item [int] chosen;
	string raw = get_property(AR_ITEMS);
	if (raw == "") return chosen;

	int n = 0;
	foreach i, piece in raw.split_string(",") {
		string id = piece;
		while (id.starts_with(" ")) id = id.substring(1, id.length());
		while (id.ends_with(" ")) id = id.substring(0, id.length() - 1);
		if (!id.is_integer()) continue;

		item it = id.to_int().to_item();
		// A preference edited by hand, or an id KoL has since retired.
		if (it == $item[none]) continue;

		// Keep the first of a repeat rather than the last, so the order you
		// added things in is the order they stay in.
		boolean already = false;
		foreach j, have in chosen {
			if (have == it) already = true;
		}
		if (already) continue;

		chosen[n] = it;
		n = n + 1;
	}
	return chosen;
}

boolean arHasTicket(item it) {
	foreach i, have in arTickets() {
		if (have == it) return true;
	}
	return false;
}

void arWriteTickets(item [int] chosen) {
	string [int] ids;
	foreach i, it in chosen ids[count(ids)] = it.to_int().to_string();
	set_property(AR_ITEMS, arJoin(ids, ","));
}

// Added at the end, so the list reads in the order you built it.
boolean arAddTicket(item it) {
	if (it == $item[none]) return false;
	if (arHasTicket(it)) return false;

	item [int] chosen = arTickets();
	chosen[count(chosen)] = it;
	arWriteTickets(chosen);
	return true;
}

boolean arRemoveTicket(item it) {
	if (!arHasTicket(it)) return false;

	item [int] chosen = arTickets();
	item [int] kept;
	foreach i, have in chosen {
		if (have == it) continue;
		kept[count(kept)] = have;
	}
	arWriteTickets(kept);
	return true;
}

// --- The other settings ----------------------------------------------------

int arCount() {
	string set = get_property(AR_COUNT);
	int n = set.is_integer() ? set.to_int() : 0;
	return n > 0 ? n : AR_COUNT_DEFAULT;
}

// The price restock parks at.
//
// Parking rather than pricing: between raffles the tickets sit in the store
// where nobody can buy them, so that announcing one is a price change and not
// a scramble to list a dozen items. Dropping to the ticket price is the first
// half of running a raffle and is not here.
int arParkPrice() {
	string set = get_property(AR_PARK);
	int n = set.is_integer() ? set.to_int() : 0;
	if (n < 1 || n > AR_MALL_MAX) return AR_MALL_MAX;
	return n;
}

// The minimum KoL will let you sell one for, which is what a ticket is
// normally priced at. An item with no autosell value floors at 100.
int arMinPrice(item it) {
	int twice = it.autosell_price() * 2;
	return twice > 100 ? twice : 100;
}

// --- Where restocking may draw from ----------------------------------------
//
// Five places, in the order they are drawn from: what is already in hand, then
// the two that cost nothing, then a Ronin pull, then meat. The order is fixed;
// what is switched on is yours.

string [int] arAllSources() {
	string [int] places;
	places[0] = "inventory";
	places[1] = "closet";
	places[2] = "display";
	places[3] = "storage";
	places[4] = "mall";
	return places;
}

boolean arIsSource(string place) {
	foreach i, known in arAllSources() {
		if (known == place) return true;
	}
	return false;
}

// The mall is off unless you say otherwise: every other source moves something
// you already own, and that one spends meat.
string AR_SOURCES_DEFAULT = "inventory,closet,display,storage";

boolean [string] arSources() {
	boolean [string] on;
	string raw = get_property(AR_SOURCES);
	if (raw == "") raw = AR_SOURCES_DEFAULT;

	foreach i, piece in raw.split_string(",") {
		string place = piece;
		while (place.starts_with(" ")) place = place.substring(1, place.length());
		while (place.ends_with(" ")) place = place.substring(0, place.length() - 1);
		if (arIsSource(place)) on[place] = true;
	}
	return on;
}

// --- The maximizer's terms, in preferences of this script's own -------------
//
// The two controls that decide what buying from the mall is allowed to cost
// are the maximizer's, laid out its way and meaning what they mean there. They
// are read from it and never written back to it: MaximizerFrame reads those
// preferences once when its window is built and never writes them, so they are
// what Preferences -> Maximizer sets. Writing them from here would change what
// the maximizer does the next time somebody runs it, which is a thing that
// spends meat on a different day for a different reason.
//
// So an unset setting here falls back to the maximizer's, and the two agree
// until you change one. Another project's gear_source.ash reached the same
// conclusion for equipment, the hard way; this is the same rule, restated,
// because this repository cannot import that one.

record arLimits {
	int priceLevel;        // 0 don't check the mall, 1 buyable only
	int maxPrice;          // the most this will pay for one, after the fallback
	string maxPriceFrom;   // which preference that came from, for the page to say

	boolean mallOpen;      // can_interact(): out of Ronin, so the mall is reachable
	boolean caseOpen;      // you cannot take things out of a display case in Ronin
	int pulls;             // -1 unlimited, 0 none left, n in Ronin
	string limited;        // limit_mode(): "" in ordinary play
	int meat;
};

arLimits arLimitsNow() {
	arLimits l;

	string level = get_property(AR_PRICE_LEVEL);
	l.priceLevel = (level == "" ? get_property("maximizerPriceLevel") : level).to_int();

	// An unset price and a price of zero are not the same thing: unset means
	// "whatever the maximizer's field says", zero means the field was emptied,
	// and both then fall through to the preference the "buy" command uses.
	string typed = get_property(AR_MAX_PRICE);
	l.maxPrice = (typed == "" ? get_property("maximizerMaxPrice") : typed).to_int();
	l.maxPriceFrom = typed == "" ? "maximizerMaxPrice" : AR_MAX_PRICE;
	if (l.maxPrice <= 0) {
		l.maxPrice = get_property("autoBuyPriceLimit").to_int();
		l.maxPriceFrom = "autoBuyPriceLimit";
	}

	l.mallOpen = can_interact();
	l.caseOpen = can_interact();
	l.pulls = pulls_remaining();
	l.limited = limit_mode();
	l.meat = my_meat();

	return l;
}

// --- What each place has, and whether it will hand it over ------------------

// Worn pieces count: you own the hat on your head.
int arInHand(item it) {
	return item_amount(it) + equipped_amount(it);
}

int arAvailable(item it, string place) {
	switch (place) {
		case "inventory": return arInHand(it);
		case "closet": return closet_amount(it);
		case "display": return display_amount(it);
		case "storage": return storage_amount(it);
		// Not a count of anything you have. The mall's answer is "as many as
		// you can pay for", so the row says the price and the restock decides.
		case "mall": return 0;
	}
	return 0;
}

// Why a place will not hand anything over right now, or "" when it will.
//
// Said rather than hidden, the way the Hat Table says it: an item in the case
// is still worth knowing about in Ronin, it just isn't worth clicking.
string arShutBecause(string place, item it, arLimits l) {
	if (l.limited != "") return "not while " + l.limited;

	switch (place) {
		case "display":
			// KoL: "While in Hardcore or Ronin mode, you can put items in the
			// case, but not take them out."
			return l.caseOpen ? "" : "cannot take things out in Ronin";
		case "storage":
			// -1 is unlimited, out of Ronin. 0 is Hardcore, or a Ronin day
			// already spent.
			return l.pulls == 0 ? "no pulls left today" : "";
		case "mall":
			if (!l.mallOpen) return "the mall is shut in Ronin";
			if (!it.is_tradeable()) return "not tradeable";
			if (l.priceLevel == 0) return "mall prices are switched off";
			int price = it.mall_price();
			if (price <= 0) return "no mall price";
			if (price > l.maxPrice) {
				return "over your limit (" + l.maxPrice + ", " + l.maxPriceFrom + ")";
			}
			return "";
	}
	return "";
}

// --- One ticket's row ------------------------------------------------------

record arSource {
	string place;
	int available;      // how many that place holds; 0 for the mall, see above
	boolean enabled;    // whether your settings let restock use it
	string shut;        // why it cannot be used now, or ""
	int price;          // the mall's, for the mall; 0 elsewhere
};

record arRow {
	item it;
	int id;
	string name;
	string image;

	int inStore;        // how many are listed
	int storePrice;     // what they are listed at, 0 when none are
	int storeLimit;     // the per-day limit on the listing
	boolean parked;     // listed, at the parking price, all of them

	int want;           // arCount()
	int shortfall;      // how many more the store needs
	int reachable;      // how many the enabled, open sources could supply

	int mallPrice;
	int minPrice;       // what a ticket would cost a player
	boolean tradeable;

	arSource [int] sources;
};

arRow arRowFor(item it, arLimits l) {
	arRow r;
	r.it = it;
	r.id = it.to_int();
	r.name = it.to_string();
	r.image = it.image;

	r.inStore = it.shop_amount();
	r.storeLimit = it.shop_limit();
	// shop_price() answers MALL_MAX for an item that is not in the store at
	// all (StoreManager.getPrice starts at MALL_MAX and returns it if it finds
	// no listing), which reads as "parked" when the parking price is the same
	// number -- and is the default. Nothing is listed, so nothing is priced.
	r.storePrice = r.inStore > 0 ? it.shop_price() : 0;

	r.want = arCount();
	r.shortfall = r.want - r.inStore;
	if (r.shortfall < 0) r.shortfall = 0;
	r.parked = r.inStore >= r.want && r.storePrice == arParkPrice();

	r.mallPrice = it.is_tradeable() ? it.mall_price() : 0;
	r.minPrice = arMinPrice(it);
	r.tradeable = it.is_tradeable();

	boolean [string] on = arSources();
	r.reachable = 0;
	foreach i, place in arAllSources() {
		arSource s;
		s.place = place;
		s.available = arAvailable(it, place);
		s.enabled = on contains place;
		s.shut = arShutBecause(place, it, l);
		s.price = place == "mall" ? r.mallPrice : 0;
		r.sources[count(r.sources)] = s;

		if (s.enabled && s.shut == "") r.reachable = r.reachable + s.available;
	}

	return r;
}

arRow [int] arRows() {
	arLimits l = arLimitsNow();
	arRow [int] rows;
	foreach i, it in arTickets() rows[count(rows)] = arRowFor(it, l);
	return rows;
}

// --- What has sold ---------------------------------------------------------
//
// get_shop_log() hands back one string per sale, newest first, each of them
// KoLmafia's own "<id>: " and then KoL's line verbatim:
//
//     0: 10/21/26 10:22:48 Someone bought 29 (fizzing spore pod) for 20300 Meat.
//
// Read off the real log rather than assumed. Two things in it decide the
// pattern: a KoL name can contain spaces, so the buyer is whatever sits
// between the time and " bought "; and an item name can contain brackets and
// apostrophes, so the name is whatever sits between the first "(" and the last
// ") for ". Both are lazy-then-greedy rather than clever.

record arSale {
	int id;             // KoLmafia's line number: newest first, so 0 is newest
	string stamp;       // "10/21/26 10:22:48"
	string date;
	string time;
	string buyer;
	int qty;
	string name;        // the item as the log spells it
	item it;            // $item[none] when the log's name doesn't resolve
	int meat;
	boolean parsed;
	string raw;         // always kept, so an unparsed line can still be shown
};

arSale arParseSale(string line) {
	arSale s;
	s.raw = line;
	s.parsed = false;
	s.id = -1;

	matcher m = create_matcher(
		"^(\\d+): (([0-9/]+) ([0-9:]+)) (.+?) bought ([0-9,]+) \\((.*)\\) for ([0-9,]+) Meat\\.?$",
		line);
	if (!m.find()) return s;

	s.id = m.group(1).to_int();
	s.stamp = m.group(2);
	s.date = m.group(3);
	s.time = m.group(4);
	s.buyer = m.group(5);
	// to_int() stops at the comma, so the separators go first. Not chained off
	// replace_string(): calling to_int() on its result returns 0.
	string qty = m.group(6).replace_string(",", "");
	s.qty = qty.to_int();
	s.name = m.group(7);
	string meat = m.group(8).replace_string(",", "");
	s.meat = meat.to_int();
	s.it = s.name.to_item();
	s.parsed = true;

	return s;
}

arSale [int] arSales() {
	arSale [int] sales;
	foreach i, line in get_shop_log() sales[count(sales)] = arParseSale(line);
	return sales;
}

// Only the tickets, which is what a raffle is about; everything else in the
// store is an ordinary sale.
arSale [int] arTicketSales() {
	boolean [item] chosen;
	foreach i, it in arTickets() chosen[it] = true;

	arSale [int] kept;
	foreach i, s in arSales() {
		if (!s.parsed) continue;
		if (!(chosen contains s.it)) continue;
		kept[count(kept)] = s;
	}
	return kept;
}

// --- JSON ------------------------------------------------------------------

// A name as plain text.
//
// KoL writes its own HTML entities into the names themselves and KoLmafia
// keeps them exactly as it was given them: the item really is called
// `&quot;DRINK ME&quot; potion`, and a couple of hundred others carry a
// `&trade;` or an `&eacute;`. That is fine while a name is going into HTML,
// which is where the gCLI's print_html() puts it -- and wrong everywhere the
// relay page puts it, because the page builds text nodes and a text node shows
// you the entity.
//
// So the decode happens here rather than at each of the dozen places a name is
// written, and it happens on the way out to the page rather than on the way in
// from KoLmafia, which is still the one that owns the name.
string arPlain(string name) {
	return name.entity_decode();
}

// Everything the page is handed goes through this: an item name KoL chose, a
// buyer name somebody else chose, and this script's own words. Decoded first,
// then escaped for JSON, because the page renders all of it as text.
string arQuoted(string value) {
	string out = arPlain(value);
	out = out.replace_string("\\", "\\\\");
	out = out.replace_string("\"", "\\\"");
	out = out.replace_string("\n", " ");
	out = out.replace_string("\r", " ");
	out = out.replace_string("\t", " ");
	return "\"" + out + "\"";
}
