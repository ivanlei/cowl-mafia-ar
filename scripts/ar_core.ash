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
// error, and every other script somebody has installed shares those folders.
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

// --- The list a fresh install starts with ----------------------------------
//
// Seventy-five items that make reasonable tickets. Every one of them is
// tradeable, and every one was worth more than the minimum price it can be
// sold at when this was written -- checked against KoLmafia's own historical
// prices, since an item worth more than it sells for is the whole definition
// of a ticket. They spread across food, drink, one-day passes, the pastes and
// a few oddities, so a channel seeing several of them in a week sees variety.
//
// Nothing reads this unless you ask for it -- the "Default items" button on
// the Tickets tab, or `ar defaultitems`. It is not a fallback for an empty
// list: a list that refills itself when you empty it cannot be emptied, and
// telling "never chosen" from "chosen nothing" needs machinery that a button
// does not. Your tickets are whatever you last said they were.
//
// Ids, for the reason the preference stores ids: a name can contain a comma,
// which is the separator, and KoL renames things. The name beside each is
// what that id was called when this was written, and is a comment -- nothing
// reads it.
string [int] arDefaultTicketIds() {
	string [int] ids;
	void add(int id) { ids[count(ids)] = id.to_string(); }

	add(10881);   // 11-leaf clover
	add( 9991);   // absentee voter ballot
	add( 4001);   // agua de vida
	add( 7045);   // antimatter wad
	add( 9879);   // bad rum and good cola
	add(10744);   // battery (car)
	add( 8545);   // blood-drive sticker
	add( 1416);   // blue snowcone
	add( 1624);   // blue-frosted astral cupcake
	add( 5226);   // box of Familiar Jacks
	add(10056);   // Boxing Day Pass
	add( 5227);   // bucket of wine
	add( 1593);   // cold hi mein
	add( 5260);   // cold-filtered water
	add( 3028);   // Corpse Island iced tea
	add( 9204);   // counterfeit city
	add(10070);   // Crimboysters Rockefeller
	add(11738);   // crystallized pumpkin spice
	add( 8635);   // cuppa Royal tea
	add( 8634);   // cuppa Sobrie tea
	add( 8633);   // cuppa Voraci tea
	add( 9479);   // Daily Affirmation: Always be Collecting
	add(11346);   // day shortener
	add( 5206);   // demonic paste
	add( 6565);   // Dreadsylvanian cold pocket
	add( 6573);   // Dreadsylvanian slithery nipple
	add( 5201);   // ectoplasmic paste
	add( 5216);   // elemental paste
	add( 8553);   // emergency margarita
	add( 4609);   // essential tofu
	add(11347);   // extra time
	add( 3327);   // extra-greasy slider
	add( 7101);   // Five Second Energy™
	add( 3324);   // Frosty's frosty mug
	add( 5459);   // fudge spork
	add( 8392);   // gift card
	add( 5209);   // goblin paste
	add( 5198);   // gooey paste
	add( 5202);   // greasy paste
	add( 1625);   // green-frosted astral cupcake
	add( 7065);   // grim fairy tale
	add( 7061);   // grimstone mask
	add( 5379);   // groose grease
	add( 9036);   // hacked gibson
	add( 1592);   // hot hi mein
	add( 8698);   // iced plum wine
	add( 3325);   // jar of fermented pickle juice
	add( 8993);   // jumping horseradish
	add( 7797);   // karma shawarma
	add( 3353);   // llama lama gong
	add( 7133);   // lupine appetite hormones
	add(11645);   // Mmm-brr! brand mouthwash
	add( 2614);   // mojo filter
	add( 8823);   // Mr. Burnsger
	add(11622);   // muscular soup
	add( 9943);   // Neverending Party guest pass
	add( 5200);   // oily paste
	add( 8204);   // one-day ticket to Dinseylandfill
	add( 8486);   // one-day ticket to That 70s Volcano
	add( 8737);   // perfect cosmopolitan
	add( 8739);   // perfect dark and stormy
	add( 8740);   // perfect mimosa
	add( 8738);   // perfect negroni
	add( 8741);   // perfect old-fashioned
	add( 8742);   // perfect paloma
	add( 9537);   // pocket wish
	add( 9761);   // Poké-Gro fertilizer
	add( 4412);   // quantum taco
	add( 4497);   // recording of The Ballad of Richie Thingfinder
	add( 5471);   // resolution: be more adventurous
	add( 8994);   // Sacramento wine
	add( 1596);   // sleazy hi mein
	add( 8088);   // solid gold jewel
	add( 3433);   // spice melange
	add( 9496);   // splendid martini

	return ids;
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

// An item's name to show someone.
//
// to_string() on an item whose name another item shares answers
// "[2325]Staff of Ed" -- KoLmafia disambiguating, since the name alone does
// not say which one. Everywhere this is shown the id is shown beside it
// already, so the prefix is a second copy of the answer wearing brackets.
string arItemName(item it) {
	string name = it.to_string();
	matcher m = create_matcher("^\\[\\d+\\](.+)$", name);
	return m.find() ? m.group(1) : name;
}

// --- Where restocking may draw from ----------------------------------------
//
// Four places, in the order they are drawn from: what is already in hand,
// then the two that cost nothing, then a Ronin pull. The order is fixed; which
// of them are switched on is yours.
//
// There is deliberately no fifth. Buying tickets would make hosting a raffle
// something that spends meat, and every one of these moves something you
// already own from one place you own to another.

string [int] arAllSources() {
	string [int] places;
	places[0] = "inventory";
	places[1] = "closet";
	places[2] = "display";
	places[3] = "storage";
	return places;
}

boolean arIsSource(string place) {
	foreach i, known in arAllSources() {
		if (known == place) return true;
	}
	return false;
}

// All of them, since none of them costs anything.
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

// --- Whether a place will hand something over today ------------------------

record arLimits {
	boolean caseOpen;      // you cannot take things out of a display case in Ronin
	int pulls;             // -1 unlimited, 0 none left, n in Ronin
	string limited;        // limit_mode(): "" in ordinary play
};

arLimits arLimitsNow() {
	arLimits l;
	l.caseOpen = can_interact();
	l.pulls = pulls_remaining();
	l.limited = limit_mode();
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
	}
	return 0;
}

// Why a place will not hand anything over right now, or "" when it will.
//
// Said rather than hidden, the way the Hat Table says it: an item in the case
// is still worth knowing about in Ronin, it just isn't worth clicking.
string arShutBecause(string place, arLimits l) {
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
	}
	return "";
}

// --- One ticket's row ------------------------------------------------------

record arSource {
	string place;
	int available;      // how many that place holds
	boolean enabled;    // whether your settings let restock use it
	string shut;        // why it cannot be used now, or ""
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
	r.name = arItemName(it);
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

	// What it goes for, which is the whole question about a ticket: a ticket
	// is an item worth more than it is being sold for. Looking a price up is
	// not buying anything -- nothing here spends meat -- but it is a mall
	// search, so it is read once per row and not per keystroke.
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
		s.shut = arShutBecause(place, l);
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
//
// Takes the log rather than reading it, because every caller also wants to
// count the lines that could not be read, and get_shop_log() is a
// ManageStoreRequest -- a round trip to KoL. Reading it twice per command was
// two trips and two "Examining store logs..." in the gCLI.
arSale [int] arTicketsAmong(arSale [int] all) {
	boolean [item] chosen;
	foreach i, it in arTickets() chosen[it] = true;

	arSale [int] kept;
	foreach i, s in all {
		if (!s.parsed) continue;
		if (!(chosen contains s.it)) continue;
		kept[count(kept)] = s;
	}
	return kept;
}

// How many lines of a log could not be read at all. Worth saying out loud:
// one of them could have been a ticket sale, and leaving them out silently
// would be reporting that there were none.
int arUnreadable(arSale [int] all) {
	int n = 0;
	foreach i, s in all {
		if (!s.parsed) n = n + 1;
	}
	return n;
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
