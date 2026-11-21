// care_relay.ash -- who in the clan is active, who has already had a care
// package, and what they would get.
//
// No main(), deliberately: a relay override cannot be imported by anything that
// has one too (see mall_price.ash), so all of this lives here where
// tests/care_packages.test.ash can reach it and relay_Care_Packages.ash is a
// shell that only draws.
//
// NOTHING IN THIS FILE SENDS ANYTHING. It reads the roster, the profiles and
// the mailboxes, and works out who would get a package. The sending lives in
// its own file so that "does this page send" is answered by which files exist
// rather than by reading them -- the same reason sendmessage.ash says so in
// capitals.
//
// Three things it has to ask KoL about, and what each costs:
//
//   the roster        clan_members.php, one request per 35 members (3 today).
//                     Name, id, rank and title; NO last login -- neither this
//                     page nor clan_detailedroster.php carries one.
//   each last login   showplayer.php?who=<id>, one request PER MEMBER. This is
//                     the expensive part.
//   who already had   messages.php, TWO requests for the whole history. See
//                     careAlreadySent().
//
// WHEN EACH OF THOSE HAPPENS, which is the thing this file was reorganised
// around (2026-11-21). Drawing the page does the mailbox read and nothing else:
// the roster and the logins are read off disk, held for careHoldDays(), and
// refreshed only when somebody presses the button that drives ar_care_scan.ash.
// It used to walk the roster and spend eighty profile fetches inside the page
// render, which took about eight seconds, could not report progress, and then
// asked you to reload to do the next eighty.

// Shares this repository's own item sourcing with the anti-raffle: where a
// thing may be taken from, whether that place will hand it over today, and how
// many are there. An anti-raffle restocking its tickets and a care package
// being packed are the same question, so they ask it the same way rather than
// each keeping an answer.
import <ar_core.ash>

/*****************************************************
	Writing somebody else's words into a page
*****************************************************/

// EVERY STRING THIS PAGE DRAWS THAT IT DID NOT WRITE ITSELF goes through one
// of these two. There are three sources of such a string and all three are
// outside our control: a player's name and their clan rank, both typed by
// whoever runs the clan, and the package note, which is now a text box on the
// page rather than a preference only the gCLI could reach.
//
// None of it was escaped before (2026-11-21). A rank called "Skills & Crap"
// has always rendered wrong; what made it worth fixing rather than noting is
// the note becoming editable, because the page round-trips it back into an
// <input value=...> and a quote in it would end the attribute early.
//
// entity_encode() is KoLmafia's own (CharacterEntities.escape). It encodes
// " & < > and every non-ASCII character, and leaves the rest of ASCII alone.
//
// IT DOES NOT ENCODE THE APOSTROPHE -- checked in CharacterEntities.java
// rather than assumed, where the table runs &quot; &amp; &lt; &gt; and no
// &apos;. This page quotes its attributes with single quotes nearly
// everywhere, so "it's a gift" in the note would break out of a single-quoted
// value and leave the rest of the tag as text. Hence careAttr(), which
// supplies DOUBLE quotes around a value and is the only way an untrusted
// string should ever reach an attribute here.
string careHtml(string text) {
	return entity_encode(text);
}

// The whole attribute value, quotes included: write `value=` + careAttr(s),
// never `value='` + something + `'`. Returning the quotes rather than trusting
// the caller to type the right ones is the point -- it is the half of this
// that cannot be got wrong by habit.
string careAttr(string value) {
	return "\"" + entity_encode(value) + "\"";
}

/*****************************************************
	Preferences
*****************************************************/

// Named the way this repository names its own (arTicketItems, arRestockCount).
// The prefix is not decoration: KoLmafia preferences are one namespace shared
// with every script installed, the same way relay/ and scripts/ are, and so is
// the data/ folder the cache below sits in.
//
// Set them with KoLmafia's `set`, or from Preferences in the Swing client --
// or, for the three the Config box carries a control for, from the page
// itself. ar_care_prefs.ash is the endpoint that writes those three and
// refuses everything else, the way ar_prefs.ash does for the anti-raffle's;
// careBadValue() below is the rule it refuses by, kept here rather than in the
// endpoint so that a test can reach it without a running relay.
string CARE_DAYS    = "arCareDays";
string CARE_PACKAGE = "arCarePackage";
string CARE_MEAT    = "arCareMeat";
string CARE_SOURCES  = "arCareSources";
string CARE_NOTE    = "arCareNote";
string CARE_HOLD    = "arCareHoldDays";
string CARE_BATCH   = "arCareScanBatch";
string CARE_PAUSE   = "arCareScanPause";

int CARE_DAYS_FALLBACK = 14;

// HOW LONG A SCAN IS KEPT, and the one thing that distinguishes this page from
// the version that annoyed whoever opened it: nothing here is fetched unless
// somebody presses the button, so what is on disk is what the page draws until
// it is a week old.
//
// Seven days, which is a REAL TRADE and not a free one. A last login read a
// week ago can say "quiet" about somebody who came back on Tuesday, and
// careDays() is normally 14 -- so a 7-day-old snapshot can be wrong about a
// member in exactly one direction: left out of a send they should have had.
// The page answers that by saying how old the snapshot is, in its header, every
// time it draws; a decision made on six-day-old logins is visibly made on
// six-day-old logins. The previous version instead re-read everything every
// twelve hours, which is where the eight-second page load came from.
int CARE_HOLD_FALLBACK = 7;

// A SCAN'S RATE, as a batch and a pause rather than a single "per second",
// because those are the two numbers the two halves actually use: the endpoint
// fetches `batch` profiles in one request, and the page waits `pause` ms before
// asking for the next lot. 5 and 1000ms is about three a second measured
// against a profile's own ~100ms, so a 216-member clan is about 75 seconds.
//
// Preferences and not constants because the right rate is a judgement about
// somebody else's server, and the person running it should be able to be
// kinder without editing a script.
int CARE_BATCH_FALLBACK = 5;
int CARE_PAUSE_FALLBACK = 1000;

// A batch of zero or a negative one would be a loop that asks forever and
// never fetches, so both fall back rather than being passed on. The ceiling is
// the same reasoning in the other direction: a batch big enough to sit in one
// request for a minute is a request KoLmafia is holding a slot open for.
int CARE_BATCH_MAX = 25;

int careHoldDays() {
	int n = get_property(CARE_HOLD).to_int();
	return n > 0 ? n : CARE_HOLD_FALLBACK;
}

int careHoldSeconds() { return careHoldDays() * 24 * 60 * 60; }

int careScanBatch() {
	int n = get_property(CARE_BATCH).to_int();
	if (n < 1) return CARE_BATCH_FALLBACK;
	return n > CARE_BATCH_MAX ? CARE_BATCH_MAX : n;
}

// Zero IS allowed here, and means "as fast as it answers". A negative one is a
// typo rather than an intention.
//
// THE EMPTY CHECK IS THE WHOLE FUNCTION. An unset preference is "" and
// to_int()s to 0, and 0 is a value this one deliberately honours -- so without
// asking first, never having set the preference would silently mean the fastest
// possible scan, which is the opposite of what the default is for. The other
// two above are safe from this only because 0 is not meaningful to them.
int careScanPause() {
	string raw = get_property(CARE_PAUSE);
	if (raw == "" || !raw.is_integer()) return CARE_PAUSE_FALLBACK;
	int n = raw.to_int();
	return n >= 0 ? n : CARE_PAUSE_FALLBACK;
}

// THE PACKAGE IS EMPTY UNTIL YOU SET IT, and the page offers no send button
// while it is. A tool that gives your items away should not arrive with an
// opinion about which ones.
string carePackage() { return get_property(CARE_PACKAGE); }

int careDays() {
	int n = get_property(CARE_DAYS).to_int();
	return n > 0 ? n : CARE_DAYS_FALLBACK;
}

int careMeat() {
	int n = get_property(CARE_MEAT).to_int();
	return n > 0 ? n : 0;
}

// THREE PLACES, NOT THE ANTI-RAFFLE'S FOUR: Hagnk's storage is not a source a
// care package may be packed from at all. COwliCK's call, 2026-11-21, asked
// before anything was built on it.
//
// A pull out of storage costs one of the twenty a day Ronin allows, and those
// are worth more than a present. The anti-raffle keeps storage because
// restocking a store is a different trade -- which is the same reasoning that
// gave care packages their own preference in the first place, now followed
// through to its end: this does not merely default storage off, it refuses to
// accept it (ar_care_prefs.ash), so a hand-written preference cannot put back
// a source the page does not show.
string [int] careAllSources() {
	string [int] places;
	places[0] = "inventory";
	places[1] = "closet";
	places[2] = "display";
	return places;
}

boolean careIsSource(string place) {
	foreach i, known in careAllSources() {
		if (known == place) return true;
	}
	return false;
}

// KoL's own name for a place, for the Config box's checkboxes. The keys are
// this repository's internal words and two of the three happen to read as
// English; "display" does not, and "Display Case" is what the game calls it.
//
// Beside careAllSources() so that adding a place and naming it are one edit,
// and pinned by a test so that adding one and NOT naming it is a failure
// rather than a checkbox labelled with a lowercase key.
string careSourceName(string place) {
	if (place == "inventory") return "Inventory";
	if (place == "closet")    return "Closet";
	if (place == "display")   return "Display Case";
	return place;
}

// All three, since none of the three costs anything.
string CARE_SOURCES_DEFAULT = "inventory,closet,display";

// Where a package may be packed from, as a set of this repository's own source
// names. Unset means all three.
//
// AN UNKNOWN PIECE IS DROPPED RATHER THAN REFUSED, which is what makes the
// narrowing above safe to land on a preference somebody already has: a saved
// "inventory,closet,display,storage" reads as the three, rather than as an
// error on a page that cannot show one. The endpoint is where a value being
// written now is refused.
boolean [string] careSources() {
	boolean [string] on;
	string raw = get_property(CARE_SOURCES);
	if (raw == "") raw = CARE_SOURCES_DEFAULT;

	foreach i, piece in raw.split_string(",") {
		string place = piece;
		while (place.starts_with(" ")) place = place.substring(1, place.length());
		while (place.ends_with(" ")) place = place.substring(0, place.length() - 1);
		if (careIsSource(place)) on[place] = true;
	}
	return on;
}

// How many of something a package could actually be packed with right now:
// what the enabled places hold, minus the places that will not hand anything
// over today -- a display case is shut in Ronin, and limit_mode() closes the
// lot. arShutBecause() is the anti-raffle's answer to the same question.
int careReachable(item it, arLimits l) {
	boolean [string] on = careSources();
	int total = 0;
	foreach i, place in careAllSources() {
		if (!(on contains place)) continue;
		if (arShutBecause(place, l) != "") continue;
		total = total + arAvailable(it, place);
	}
	return total;
}

/*****************************************************
	What is in a package
*****************************************************/

// One entry of arCarePackage, in KoLmafia's own item-list syntax: an optional
// count, then a name or a [id].
record care_part {
	int qty;        // 1 unless the entry led with a count
	item what;      // $item[none] when the name resolves to nothing
	string named;   // the name as written, so a refusal can say which one
};

// arCarePackage, read.
//
// NEVER FAILS. A name that is not an item comes back as $item[none] with
// `named` kept, because every caller wants to say something about the bad
// entry rather than be handed a list that is quietly one shorter.
//
// Lifted out of carePackageProblems(), which is where this loop used to live
// and still used to be the only reading of the preference. The Package box
// draws a row per part and the endpoint validates a list before storing it,
// so there are three readers now and they must agree on all of it -- where
// the count stops, what counts as an entry, how a blank is treated.
care_part careOnePart(string entry) {
	string want = entry;
	while (want.starts_with(" ")) want = want.substring(1, want.length());
	while (want.ends_with(" ")) want = want.substring(0, want.length() - 1);

	care_part p;
	p.qty = 1;
	p.named = want;
	if (want == "") return p;

	// to_item of a leading count does not resolve, so the count comes off
	// first. "3 soda water" is one entry, not three.
	matcher counted = create_matcher("^(\\d+)\\s+(.*)$", want);
	if (counted.find()) {
		p.qty = counted.group(1).to_int();
		p.named = counted.group(2);
	}
	p.what = p.named.to_item();
	return p;
}

care_part [int] carePackageParts(string list) {
	care_part [int] parts;
	foreach i, piece in split_string(list, ",") {
		care_part p = careOnePart(piece);
		if (p.named == "") continue;
		parts[count(parts)] = p;
	}
	return parts;
}

// THE SAME ENTRIES, ONE PER LINE, which is what the Package box sends and is
// a different format from the one above on purpose.
//
// The stored format is KoLmafia's, comma-separated, and a comma-separated
// list cannot carry an item with a comma in its name -- of which COwliCK
// holds four right now ("Oh, the Humanitini", "Ouija Board, Ouija Board",
// "Maxing, Relaxing", "My Life of Crime, a Memoir"), all giftable. Picking
// one from the box and sending it as part of a comma list would arrive as two
// entries that each resolve to nothing, and the box would say "that is not an
// item" about an item it had just suggested.
//
// So the browser sends newline-separated entries, which no item name
// contains, and ar_care_prefs.ash converts to the stored form with
// carePackageList() -- which knows to write the awkward ones as [id].
care_part [int] carePartsFromLines(string lines) {
	care_part [int] parts;
	foreach i, line in split_string(lines, "\n") {
		care_part p = careOnePart(line);
		if (p.named == "") continue;
		parts[count(parts)] = p;
	}
	return parts;
}

// How one part is written so that reading it back gives the same part.
//
// A COMMA IN THE NAME IS WHY THIS EXISTS. The list is comma-separated and
// plenty of real items have a comma in them -- "Trash, a Memoir", "Oh, the
// Humanitini", "1,970 carat gold", "holy bomb, batman" -- all tradeable, all
// giftable, all of which would split into two entries that each resolve to
// nothing. So those are written as KoLmafia's bracketed id form instead,
// which is the same item-list syntax and has no comma in it
// (ItemDatabase.getBracketedItemId: "[8254]" resolves, and to_item reads it).
//
// Only those. A package written as ids throughout would be a preference
// nobody could read or edit by hand, and the whole point of using KoLmafia's
// syntax is that `set arCarePackage = 3 soda water` still works.
string carePackageTerm(care_part p) {
	if (p.what == $item[none]) return p.named;
	string name = p.what.to_string();
	return name.contains_text(",") ? "[" + p.what.to_int() + "]" : name;
}

// The parts, back to the preference. What the Package box saves.
// EVERY PART, INCLUDING A BAD ONE. Dropping a quantity of zero here looked
// tidy and was the wrong shape: careBadValue() refuses "send at least one of
// each item", and a zero quietly filtered out before it got there meant the
// rule was unreachable and a row typed as 0 vanished without a word instead
// of being refused. Clearing the item name is how a row is removed; this
// writes what it was given.
string carePackageList(care_part [int] parts) {
	buffer out;
	foreach i, p in parts {
		if (out.length() > 0) out.append(", ");
		out.append(p.qty + " " + carePackageTerm(p));
	}
	return out.to_string();
}

// The package in words, for a sentence somebody reads.
//
// NOT carePackage() ITSELF, which is the stored form and may hold a bracketed
// id: the summary line said "190x (2 soda water, 1 [5590])" the first time it
// was shown one, which is true, correct, and no use to anybody. The id is how
// the preference survives a comma; the name is what the page says.
string carePackageText(string list) {
	buffer out;
	foreach i, p in carePackageParts(list) {
		if (out.length() > 0) out.append(", ");
		out.append(p.qty + " " + (p.what == $item[none] ? p.named : p.what.to_string()));
	}
	return out.to_string();
}

string CARE_NOTE_DEFAULT = "A care package from your clan. Enjoy!";

string careNote() {
	string s = get_property(CARE_NOTE);
	return s == "" ? CARE_NOTE_DEFAULT : s;
}


/*****************************************************
	What the Config box is allowed to change
*****************************************************/

// THE THREE THE PAGE CAN WRITE, and only these three. A relay script answers
// whatever the browser asks it, and "set any preference you like" is not a
// thing to leave lying in the relay folder -- so a name that is not one of
// these is refused rather than set. ar_prefs.ash keeps the same list for the
// anti-raffle's three, and the reasoning is written out there.
//
// arCarePackage and arCareMeat joined the list when the Package box arrived
// (COwliCK, 2026-11-21: "very like the kmail item sending UI"), which
// reversed his earlier answer that the package should stay a gCLI-only
// readout. The item list is the awkward one and always was -- it has to be
// parsed against real item names and refused by name when one is wrong --
// which is why careBadValue() below is longer for it than for the rest.
//
boolean [string] careSettable() {
	boolean [string] allowed;
	allowed[CARE_DAYS] = true;
	allowed[CARE_SOURCES] = true;
	allowed[CARE_NOTE] = true;
	allowed[CARE_PACKAGE] = true;
	allowed[CARE_MEAT] = true;
	return allowed;
}

// How long a note may be. KoL's own kmail box takes far more than this; the
// cap is here so that a paste accident cannot put a novel in a preference
// file, and it is generous enough that no note anybody means to write hits it.
int CARE_NOTE_MAX = 500;

// Each setting's own rule, and "" for a value that is fine. A refusal says
// what was wrong and never repeats the value back, the same contract
// arBadValue() keeps.
//
// IN THE LIBRARY RATHER THAN THE ENDPOINT, unlike arBadValue(), for one
// reason: these are the rules a test can get at. care_packages.test.ash
// imports this file and nothing else, and a validator reachable only through
// a running relay is a validator checked by hand or not at all.
string careBadValue(string name, string value) {
	if (name == CARE_SOURCES) {
		if (value == "") return "Leave at least one place on.";
		foreach i, piece in value.split_string(",") {
			string place = piece;
			while (place.starts_with(" ")) place = place.substring(1, place.length());
			while (place.ends_with(" ")) place = place.substring(0, place.length() - 1);
			// STORAGE IS REFUSED BY NAME rather than falling through to the
			// sentence below, because it is the one wrong answer somebody has
			// a reason to try: it was a source until 2026-11-21, it still is
			// one for the anti-raffle, and a flat "not a place this knows"
			// would read as a bug rather than as a decision.
			// Plain ASCII, like every other refusal here: this sentence
			// travels as JSON and is set as textContent, so an HTML entity
			// would show up as one and a literal em dash depends on the
			// charset surviving three hops.
			if (place == "storage") {
				return "Care packages are not packed from Hagnk's: "
					+ "a pull costs one of the day's twenty.";
			}
			if (!careIsSource(place)) return "Not a place this knows.";
		}
		return "";
	}

	if (name == CARE_NOTE) {
		// EMPTY IS ALLOWED and means the default sentence back, which is how
		// careNote() already reads an unset preference. So clearing the box is
		// the way to get the default, rather than a refusal telling you to
		// type something you did not want to choose.
		if (value.length() > CARE_NOTE_MAX) return "That note is too long.";
		return "";
	}

	if (name == CARE_DAYS) {
		if (value == "" || !value.is_integer()) return "Not a number.";
		if (value.to_int() < 1) return "At least one day.";
		return "";
	}

	if (name == CARE_MEAT) {
		// Empty IS allowed and means none, because clearing the Meat box is
		// how you stop sending Meat. careMeat() already reads an unset
		// preference as 0.
		if (value == "") return "";
		if (!value.is_integer()) return "Not a number.";
		if (value.to_int() < 0) return "Meat cannot be negative.";
		return "";
	}

	if (name == CARE_PACKAGE) {
		// Empty is a package of no items, which with Meat set is a perfectly
		// good package and without it is the state a fresh install is in.
		if (value == "") return "";

		care_part [int] parts = carePackageParts(value);
		if (count(parts) == 0) return "Name an item, or leave it empty.";

		// NUMBERED, BECAUSE THE PACKAGE SAVES AS A WHOLE. A bad row blocks
		// every other row from saving, and the first version of these said
		// only "That is not an item." -- which reads as being about the row
		// you just touched. Caught within a minute of using it: a typo left
		// in row one refused a perfectly good row two, and the message
		// pointed at the wrong one.
		//
		// The position, not the value: a refusal here still never repeats
		// back what was sent, which is the contract every other one keeps.
		foreach i, p in parts {
			string which = "Item " + (i + 1);
			if (p.qty < 1) return which + " needs a quantity of at least one.";
			if (p.what == $item[none]) return which + " is not one KoL knows.";
			if (!p.what.is_giftable()) return which + " cannot be sent to anyone.";
		}

		// REFUSED HERE AS WELL AS REPORTED BY carePackageProblems(), which is
		// not a duplicate: the gCLI can still write a sixth item and the page
		// has to explain the package it finds, but the page's own controls
		// should not be able to walk into a state they then complain about.
		// KoLmafia's gift box holds five and anyone in Hardcore or Ronin can
		// only be sent a gift box.
		if (count(parts) > 5) {
			return "A gift box holds five different items, and that is "
				+ count(parts) + ".";
		}
		return "";
	}

	return "Not a setting this touches.";
}

/*****************************************************
	The marker
*****************************************************/

// HOW A CARE PACKAGE IS TOLD APART FROM AN ORDINARY KMAIL. Dedup reads your
// sent mail, and your sent mail is mostly not care packages -- there are
// ninety-odd messages in the Outbox today and they are conversations. So every
// package carries this line, and dedup counts only the sent messages that have
// it.
//
// A CONSTANT, NOT A PREFERENCE, and that is the whole point. If this were part
// of the editable note, changing the note would make every package already sent
// stop counting, and the next run would send to everyone a second time. The
// note is yours to write; the marker is not.
string CARE_MARK = "[care package]";

// The body that actually goes out: your note, then the marker on its own line.
string careBody() { return careNote() + "\n\n" + CARE_MARK; }

/*****************************************************
	The last-login cache
*****************************************************/

int CARE_LOGIN_FORMAT = 2;   // 2: care_login gained `looked`
string CARE_LOGIN_FILE = "ar_care_logins.txt";

// HOW LONG A ROW IS GOOD FOR is careHoldSeconds(), the same window the roster
// below is held for. Was a hardcoded twelve hours, which meant a page opened
// the next day re-read the whole clan eighty profiles at a time.
//
// A DELIBERATE DEPARTURE from this repo's cache-stamp convention, which is "a
// stamp of what the answer depends on" rather than a clock
// -- because another player's last login depends on nothing this character
// can observe. A clock is the only
// stamp available, so the question is only how stale is tolerable, which is now
// the reader's call rather than this file's: see CARE_HOLD_FALLBACK for what
// the week costs.
//
// PER ROW AND NOT PER SNAPSHOT, which is what makes "look up again" cheap: a
// scan re-fetches the rows that have aged out and leaves the rest alone, so a
// member looked up yesterday is not looked up again today.

record care_login {
	string lastLogin;   // KoL's own words, e.g. "November 10, 2026"
	int days;           // whole days since, or -1 for "could not tell"
	int fetchedAt;      // epoch SECONDS, so the file stays readable
	int format;
	// Whether anybody has actually looked. A row that was never fetched and a
	// row whose profile would not parse both have days = -1, and telling the
	// reader "last login unreadable" for 172 members nobody has looked at yet
	// is a lie about the data -- it reported exactly that before this existed.
	boolean looked;
};

// Read once per request and saved only if something changed: a cache across
// the rows of one page load, with the file as the cache across page loads.
//
// NOT `static`, AND THAT IS A CORRECTION. This block used to be a static one,
// under a comment saying "a relay script gets a fresh interpreter per
// request". It does not. KoLmafia caches the compiled script and a static
// scope executes only on the first run (StaticScope.execute: `if
// (!this.executed)`), so a static here keeps its value from request to
// request -- and a plain declaration is re-initialised on every invocation,
// which is what this wants.
//
// It was harmless while one script both read and wrote these files, and it
// stopped being harmless the moment ar_care_scan.ash started writing them:
// the page had read an empty cache and flagged itself as loaded, so after a
// scan wrote 239 members it went on reporting "Nothing is held yet" over a
// 16KB file. Measured, 2026-11-21, which is how this was found.
care_login [int] careLoginCache;
boolean careLoginsRead;
boolean careLoginsDirty;

void careReadLogins() {
	if (careLoginsRead) return;
	careLoginsRead = true;
	file_to_map(CARE_LOGIN_FILE, careLoginCache);

	// A shape change invalidates rather than lies. Without this, a cached row
	// written by an older version keeps its old answer until the entry happens
	// to age out, which looks exactly like the change not working.
	foreach who, entry in careLoginCache {
		if (entry.format != CARE_LOGIN_FORMAT) {
			care_login [int] empty;
			careLoginCache = empty;
			careLoginsDirty = true;
			return;
		}
	}
}

void careSaveLogins() {
	if (!careLoginsDirty) return;
	careLoginsDirty = false;
	map_to_file(careLoginCache, CARE_LOGIN_FILE);
}

// Whether this row is still good, which is one place rather than three so that
// the page's "not looked up yet", the scan's queue and the fetch itself cannot
// disagree about what fresh means.
boolean careLoginFresh(care_login entry, int nowSeconds) {
	return entry.looked && nowSeconds - entry.fetchedAt < careHoldSeconds();
}

/*****************************************************
	Parsing
*****************************************************/

// "November 10, 2026" -> whole days ago, or -1.
//
// date_to_timestamp answers `void` for anything it cannot parse (measured), and
// that lands in an int as something not worth reasoning about -- so the shape is
// checked first and a bad one is "unknown" rather than a number. Unknown is
// never treated as active: a member whose profile would not parse is left out
// of the send rather than guessed into it.
int careDaysSince(string dateText) {
	if (dateText == "") return -1;
	matcher shaped = create_matcher("^[A-Z][a-z]+ \\d{1,2}, \\d{4}$", dateText);
	if (!shaped.find()) return -1;

	int then = date_to_timestamp("MMMM d, yyyy", dateText);
	if (then <= 0) return -1;

	// now_to_int(), not gametime_to_int() -- the latter is the obvious-looking
	// one and is KoL's rollover clock, not the wall.
	return (now_to_int() - then) / (1000 * 60 * 60 * 24);
}

// A profile's last login, in KoL's own words, or "". Split from the fetch so
// tests/care_packages.test.ash can reach it: the whole reason care_relay.ash
// has no main() is that a page cannot be imported, and the same logic applies
// one level down -- a parser reachable only through a request is a parser that
// is only ever tested against the live game.
string careParseLastLogin(string page) {
	matcher found = create_matcher("<b>Last Login:</b></td><td>([^<]+)</td>", page);
	return found.find() ? found.group(1) : "";
}

// Whether a response is actually somebody's profile, the same check and for the
// same reason as careLooksLikeBox(): KoLmafia serializes its requests, so a
// relay request that lands while the gCLI is busy is answered with an empty
// page, and an empty page parses as "last login unreadable" rather than as
// nothing.
//
// IT MATTERS MORE NOW THAT A ROW IS KEPT FOR A WEEK. Caching that answer used
// to be wrong for twelve hours; under careHoldDays() it would pin "last login
// unreadable" on somebody for seven days, and no amount of pressing the button
// would shift it, because the row would look fresh. So a response that is not a
// profile is not cached at all and the member stays in the scan's queue.
//
// "Account Created:" and not "Last Login:" ON PURPOSE. The marker has to be
// independent of the field being read, or a genuine profile that simply has no
// last login would be thrown away as a failed request and re-fetched for ever.
// Checked against a live profile (30KB, 2026-11-21): the block carries Account
// Created, Last Login, Class, Sign, Gender and the three stats.
boolean careLooksLikeProfile(string page) {
	return page.contains_text("Account Created:");
}

// What KoL says instead of a date for somebody in Valhalla. Written into the
// lastLogin field, where it cannot collide with anything: every other value
// there is one of KoL's own dates, "November 10, 2026".
//
// A FIELD VALUE RATHER THAN A NEW RECORD FIELD, and that is the whole reason:
// a new field changes the shape of ar_care_logins.txt, which means bumping
// CARE_LOGIN_FORMAT, which throws away every row held and asks a 239-member
// clan to be walked again from nothing. For a state three people are ever in
// at once, that is a bad trade -- and "astral" IS the last login, as far as
// anything can tell. COwliCK asked for it in those words, 2026-11-21: "mark
// last login as astral".
string CARE_ASTRAL_LOGIN = "astral";

// SOMEBODY MID-ASCENSION, whose profile is a stub. KoL serves no Account
// Created and no Last Login for an astral spirit -- the whole page is the
// name, the id, "Level", and "Astral Spirit" -- so careLooksLikeProfile() is
// right to say it is not a profile, and before this that answer was never
// cached and the member sat in the scan queue for ever. The page then said
// "KoLmafia stopped sending profiles back", which is a lie about a server
// that answered 200 with exactly what it meant to send.
//
// ANCHORED ON THE IMAGE, not on the words. "Astral Spirit" is a phrase a
// player could put in their own profile text; /images/otherimages/spirit.gif
// is KoL's own markup for the stub and appears on nothing else. Checked
// against the real page, 2026-11-21.
boolean careLooksLikeAstral(string page) {
	return page.contains_text("otherimages/spirit.gif");
}

// WHETHER THE REQUEST CAME BACK WITH ANYTHING WORTH RECORDING, which is the
// question careLastLogin() actually asks and is worth a name of its own: the
// two ways of answering it are nothing alike, and the difference between
// "this is not an answer" and "this is an answer with no date in it" is the
// whole of the bug this was written for.
//
// Its own function so that a test can reach it. careLastLogin() cannot be
// called without a live KoL, so the decision inside it was checked by hand or
// not at all -- and reverting it to careLooksLikeProfile() alone puts the
// stuck queue straight back with nothing failing.
boolean careProfileAnswered(string page) {
	return careLooksLikeProfile(page) || careLooksLikeAstral(page);
}

record care_member {
	int who;
	string name;
	string rank;
	string title;
	boolean inactive;
};

// One roster page's rows. The real markup, as served:
//
//   <tr><td><input type=hidden name="pids[]" value=101>
//   <a class=nounder href="showplayer.php?who=101">Someone</a>&nbsp;&nbsp;</td>
//   <td>Officer</td><td>Their Title</td></tr>
//
// Parsed here rather than through KoLmafia's ClanMembersRequest, whose
// MEMBER_PATTERN wants `</a></b>&nbsp;</td>` and a numeric rank -- the
// rank-modify view, which is not what this account is served.
//
// ROW BY ROW AND THEN CELL BY CELL, rather than one pattern across the whole
// row, because the name cell is not plain text. KoL writes an inactive account
// as `<font color=gray><b> (inactive)</b></font>` after the name, and a single
// pattern with `[^<]*` between the name and the rank silently skips every one
// of those -- a miss that shows up as a shorter list rather than as an error.
// On the roster this was written against it dropped eleven members.
//
// That tag is worth having anyway: it says who is inactive for free, with no
// profile fetch, and an inactive account should not be sent anything.
void careParseRoster(string page, care_member [int] out) {
	foreach i, row in split_string(page, "<tr>") {
		matcher who = create_matcher(
			"<a class=nounder href=\"showplayer\\.php\\?who=(\\d+)\">([^<]+)</a>", row);
		if (!who.find()) continue;

		// Three cells: the name (with whatever decoration), the rank, the
		// title. Taken by position from the cells that are actually there, so
		// another tag inside one of them costs nothing.
		string [int] cells;
		matcher cell = create_matcher("<td[^>]*>(.*?)</td>", row);
		while (cell.find()) cells[count(cells)] = cell.group(1);

		care_member m;
		m.who = who.group(1).to_int();
		m.name = who.group(2);
		m.rank = count(cells) > 1 ? cells[1] : "";
		m.title = count(cells) > 2 ? cells[2] : "";
		m.inactive = row.contains_text("(inactive)");
		out[count(out)] = m;
	}
}

// Every member, across however many pages the roster has. `begin` is 1-based
// per page, and the page names the ones that exist, so this follows them rather
// than counting to a number it guessed.
care_member [int] careRoster() {
	care_member [int] all;
	boolean [int] pages;
	pages[1] = true;

	string first = visit_url("clan_members.php");
	careParseRoster(first, all);

	matcher more = create_matcher("clan_members\\.php\\?begin=(\\d+)", first);
	while (more.find()) pages[more.group(1).to_int()] = true;

	foreach p in pages {
		if (p == 1) continue;
		careParseRoster(visit_url("clan_members.php?begin=" + p), all);
	}
	return all;
}

/*****************************************************
	The roster snapshot
*****************************************************/

// THE ROSTER IS HELD TOO, which it was not before: every page load walked
// clan_members.php's three pages, and on this clan that is three requests
// before anything is drawn. Held for the same window as the logins above,
// written by one scan, and replaced whole.
//
// KEYED BY POSITION, NOT BY PLAYER ID, for one reason: an int-keyed ASH map
// iterates in ascending key order, so 0..n-1 preserves the order KoL listed
// the clan in -- and the page's sections are drawn in roster order within each
// verdict. Keyed by `who` the order would become numeric by player id, which
// is roughly account age and looks arbitrary.
int CARE_ROSTER_FORMAT = 1;
string CARE_ROSTER_FILE = "ar_care_roster.txt";

record care_saved {
	int who;
	string name;
	string rank;
	string title;
	boolean inactive;
	int savedAt;        // epoch SECONDS, as the login cache does it
	int format;
};

// Plain, not `static`, for the reason spelled out above the login cache: a
// static scope outlives the request, and another script writes this file.
care_saved [int] careRosterCache;
boolean careRosterLoaded;

void careReadRoster() {
	if (careRosterLoaded) return;
	careRosterLoaded = true;
	file_to_map(CARE_ROSTER_FILE, careRosterCache);

	// A shape change invalidates rather than lies, the same way the login cache
	// does it -- and here it matters more, because a row read with fields in
	// the wrong places would put somebody's title in their rank and silently
	// change who a rank-skip excludes.
	foreach i, row in careRosterCache {
		if (row.format != CARE_ROSTER_FORMAT) {
			care_saved [int] empty;
			careRosterCache = empty;
			return;
		}
	}
}

// When the held roster was taken, or 0 for "there isn't one". One walk writes
// every row with the same stamp, so any row answers for the snapshot; row 0 is
// just the one that always exists if any do.
int careSnapshotAt() {
	careReadRoster();
	int at = 0;
	foreach i, row in careRosterCache {
		at = row.savedAt;
		break;
	}
	return at;
}

int careSnapshotAgeSeconds() {
	int at = careSnapshotAt();
	return at == 0 ? -1 : (now_to_int() / 1000) - at;
}

boolean careSnapshotFresh() {
	int age = careSnapshotAgeSeconds();
	return age >= 0 && age < careHoldSeconds();
}

// The held roster as the rest of this file wants it. care_member rather than
// care_saved so that everything downstream -- carePlan, the rank counts, the
// page -- is reading the same record whether it came off disk or off KoL.
care_member [int] careHeldRoster() {
	careReadRoster();
	care_member [int] out;
	foreach i, row in careRosterCache {
		care_member m;
		m.who = row.who;
		m.name = row.name;
		m.rank = row.rank;
		m.title = row.title;
		m.inactive = row.inactive;
		out[count(out)] = m;
	}
	return out;
}

// REPLACED WHOLE, NEVER MERGED. A member who has left the clan has to
// disappear, and a merge would keep them -- with a rank they no longer hold,
// in a list the page then offers to send to.
void careSaveRoster(care_member [int] roster) {
	care_saved [int] fresh;
	int now = now_to_int() / 1000;
	foreach i, m in roster {
		care_saved row;
		row.who = m.who;
		row.name = m.name;
		row.rank = m.rank;
		row.title = m.title;
		row.inactive = m.inactive;
		row.savedAt = now;
		row.format = CARE_ROSTER_FORMAT;
		fresh[count(fresh)] = row;
	}
	careRosterCache = fresh;
	careRosterLoaded = true;
	map_to_file(careRosterCache, CARE_ROSTER_FILE);
}


// A member's last login, from the cache when it is fresh and from their profile
// when it is not. Spends one request from `budget` and answers an unlooked
// record when the budget is gone.
//
// ONLY THE SCAN CALLS THIS. `budget` is now a batch size -- how many profiles
// one request from the page may fetch -- rather than a page load's allowance,
// which is why the number comes from careScanBatch() and not from a constant in
// the page. It stays an int[int] because ASH passes an aggregate by reference
// and an int by value, and the whole batch has to draw on one count.
// What is on disk for this member, or an unlooked-at record. FETCHES NOTHING,
// and that is the point: the page is built out of this, so opening it costs no
// profile request at all. A member with nothing fresh here draws as "not looked
// up yet" and lands in the scan's queue.
care_login careCachedLogin(int who) {
	careReadLogins();
	int now = now_to_int() / 1000;
	if (careLoginCache contains who && careLoginFresh(careLoginCache[who], now)) {
		return careLoginCache[who];
	}

	care_login notyet;
	notyet.days = -1;
	notyet.format = CARE_LOGIN_FORMAT;
	notyet.looked = false;
	return notyet;
}

// Whether a scan still owes this member a profile fetch. One predicate for the
// queue count, the batch and the page's button label, so none of the three can
// think a different number of people are outstanding.
boolean careLoginNeeded(int who) {
	return !careCachedLogin(who).looked;
}

care_login careLastLogin(int who, int [int] budget) {
	careReadLogins();

	int now = now_to_int() / 1000;
	care_login held = careCachedLogin(who);
	if (held.looked) return held;

	care_login notyet;
	notyet.days = -1;
	notyet.format = CARE_LOGIN_FORMAT;
	notyet.looked = false;
	if (budget[0] < 1) return notyet;
	budget[0] = budget[0] - 1;

	string page = visit_url("showplayer.php?who=" + who);

	// A request that did not bring back a profile leaves NO row behind, so the
	// member stays in the queue for the next batch rather than being remembered
	// as unreadable for a week. See careLooksLikeProfile().
	//
	// The budget is still spent: the request happened. That is also what stops
	// a scan spinning on a clan KoL is refusing to answer about -- the batch
	// reports nothing fetched and the page stops asking.
	//
	// AN ASTRAL SPIRIT IS AN ANSWER, THOUGH, and has to be taken as one. Its
	// page will never have a last login on it, so leaving it uncached is not
	// "try again next batch", it is a member who can never leave the queue --
	// the scan stops one short for ever and blames KoLmafia for it.
	if (!careProfileAnswered(page)) return notyet;

	care_login entry;
	entry.lastLogin = careLooksLikeAstral(page)
		? CARE_ASTRAL_LOGIN : careParseLastLogin(page);
	// -1 either way for an astral spirit: careDaysSince() does not match
	// "astral" against its date shape, so this is belt and braces rather than
	// a second rule.
	entry.days = careDaysSince(entry.lastLogin);
	entry.fetchedAt = now;
	entry.format = CARE_LOGIN_FORMAT;
	entry.looked = true;

	careLoginCache[who] = entry;
	careLoginsDirty = true;
	return entry;
}

/*****************************************************
	Who has already had one
*****************************************************/

// The player ids you have already sent a care package to, read from your own
// sent mail -- which is the only record there is, by choice: no local ledger to
// disagree with the game.
//
// BOTH SENT BOXES, because one of them forgets. KoL says so on the pages
// themselves: the Outbox is "deleted after two weeks", and the Saved box "will
// not be deleted". So the Outbox is the recent, complete record and the Saved
// box is the permanent one, and a package is saved as it is sent (care_send.ash)
// so that it is still remembered in a month. Measured: saving COPIES rather than
// moves -- the Outbox kept its 93 while the Saved box went 54 to 55 -- and a
// saved sent message keeps its "To <name> (#id)" heading, so the two boxes parse
// the same way.
//
// TWO REQUESTS FOR THE WHOLE HISTORY, not twenty. per_page is a MULTIPLE of ten
// (the select offers 1, 2, 5, 10 for 10, 20, 50, 100 per page), so per_page=10
// returned all 93 and all 55 in one request each. Anything past 100 still pages,
// which is what the begin= loop is for.
// WHY THIS CARRIES A "read" FLAG. A relay script's visit_url can come back
// empty -- KoLmafia serializes its requests, so a page load that lands while
// the gCLI is busy gets nothing, and a roster of a couple of hundred was
// reported as "0 of 0 clan members".
//
// For the roster that is a wrong answer. For this it is a DANGEROUS one, and in
// the one direction that matters: an unread mailbox looks exactly like "nobody
// has had a package", so a send would go to everybody a second time. So it
// fails closed -- `read` false means the page refuses to offer a send at all,
// rather than offering one built on a list it could not get.
// HOW LONG A PACKAGE COUNTS AS RECENT. Two weeks, which is COwliCK's number
// and is also KoL's: the Outbox says "Messages in this mailbox will be
// deleted after two weeks", so for the Outbox alone the window and the
// mailbox agree and the filter never fires. It is here for the Saved box,
// which the same read walks and which keeps a message for ever -- without
// it, a package saved last winter would be counted as received recently.
int CARE_RECENT_DAYS = 14;

// One package, as the Outbox remembers it.
record care_gift {
	int who;
	string when;    // KoL's own words, "November 08, 2026, 06:00PM"
	int days;       // whole days ago, or -1 if the date would not parse
	string what;    // "soda water, 11 Meat", or the gift box for a wrapped one
};

record care_sent {
	boolean read;
	boolean [int] who;
	// Every marked package found, flat. Kept as a list rather than a map
	// keyed by recipient because somebody can have had two, and the count of
	// them is the whole point of the column this feeds.
	care_gift [int] gifts;
};

// What a message says arrived in it, in KoL's own words.
//
// A GIFT BOX HIDES ITS CONTENTS, and that is not a gap this can close: when
// csend falls back to a gift box for somebody in Hardcore or Ronin, the
// Outbox entry lists the BOX -- "less-than-three-shaped box" -- and nothing
// about what is inside it. So a wrapped package reads as the box it went in,
// which is honest about what the mailbox actually records.
string careGiftContents(string chunk) {
	buffer out;

	// "You acquire an item: <b>pink candy heart</b>" and the plural form
	// "You acquire <b>2 love songs of smoldering passion</b>" are one
	// pattern with an optional middle.
	matcher got = create_matcher("You acquire (?:an item: )?<b>([^<]+)</b>", chunk);
	while (got.find()) {
		if (out.length() > 0) out.append(", ");
		// KoL wraps a long name across a line and leaves the space in.
		out.append(got.group(1).replace_string("- ", "-"));
	}

	// Meat is "You gain 11 Meat." and not an acquire at all.
	matcher meat = create_matcher("You gain ([\\d,]+) Meat", chunk);
	if (meat.find()) {
		if (out.length() > 0) out.append(", ");
		out.append(meat.group(1) + " Meat");
	}
	return out.to_string();
}

// Whether a response is the mailbox that was asked for. Every one of these
// pages names itself in its own header, so its absence means the request did
// not bring back what was asked for -- an empty response because KoLmafia was
// busy, or the wrong box entirely.
//
// Split out so it can be tested, because this is the check that caught
// box=true: the mailbox was being fetched with the literal string "true" as the
// box name, and KoL answers that with a page that parses as no messages at all.
// Without this, that read as "nobody has ever had a care package".
boolean careLooksLikeBox(string page, string box) {
	return page.contains_text("Messages: " + box);
}

// Every marked recipient in one mailbox page, added to `sent`.
//
// Messages are delimited by their own checkbox, so a chunk runs from one
// `sel<id>` to the next. Split that way rather than on <tr>, because a
// message's body contains tables of its own -- every attached item is one, and
// a gift writes two rows at the same timestamp (the covering message, then the
// package with its "Inside note:").
//
// Only the chunks carrying CARE_MARK count, which is what keeps a conversation
// from reading as a care package.
void careParseSentBox(string page, care_sent sent) {
	foreach n, chunk in split_string(page, "name=\"sel\\d+\"") {
		if (!chunk.contains_text(CARE_MARK)) continue;
		matcher to = create_matcher("<b>To</b> <a href=\"showplayer\\.php\\?who=(\\d+)\"", chunk);
		if (!to.find()) continue;
		int who = to.group(1).to_int();
		sent.who[who] = true;

		// THE RECORD OF WHAT WENT, which the Packages column reads. Parsed
		// from the same chunk the marker was found in, so it costs no
		// request: the Outbox is already read in full on every page load.
		care_gift g;
		g.who = who;
		g.days = -1;
		// "<b>Date:</b> Sunday, November 08, 2026, 06:00PM". The day part is
		// the same shape careDaysSince() already reads out of a profile, so
		// the arithmetic is shared rather than written twice.
		matcher when = create_matcher("<b>Date:</b>\\s*[A-Za-z]+, ([A-Za-z]+ \\d+, \\d+)(, [\\d:]+[AP]M)?", chunk);
		if (when.find()) {
			g.when = when.group(1) + (when.group(2) == "" ? "" : when.group(2));
			g.days = careDaysSince(when.group(1));
		}
		g.what = careGiftContents(chunk);
		sent.gifts[count(sent.gifts)] = g;
	}
}

// The packages one member has had inside the window, newest first as the
// mailbox lists them.
//
// A DATE THAT WOULD NOT PARSE COUNTS. days is -1 then, and dropping those
// would quietly undercount somebody because KoL changed a date format --
// which is the opposite of what a column that exists to stop double-sending
// should do when it is unsure.
care_gift [int] careGiftsFor(care_sent sent, int who) {
	care_gift [int] mine;
	foreach i, g in sent.gifts {
		if (g.who != who) continue;
		if (g.days > CARE_RECENT_DAYS) continue;
		mine[count(mine)] = g;
	}
	return mine;
}

care_sent careAlreadySent() {
	care_sent sent;
	sent.read = true;
	// ONE LOOP VARIABLE, not two. A $strings[...] literal is a SET: the strings
	// are the KEYS and every value is `true`, so `foreach i, box in` binds the
	// name to `i` and `true` to `box` -- and this asked KoL for
	// "messages.php?box=true", which answers with a page that has no mailbox
	// header on it. The fail-closed check below is the only reason that showed
	// up as a refusal rather than as "nobody has had a package".
	foreach box in $strings[Outbox, Saved] {
		int begin = 1;
		while (begin > 0) {
			string page = visit_url("messages.php?box=" + box + "&begin=" + begin + "&per_page=10");

			// Does this even look like the mailbox? See careLooksLikeBox.
			if (!careLooksLikeBox(page, box)) {
				sent.read = false;
				return sent;
			}

			careParseSentBox(page, sent);

			// Only page on when the header says there is more. "(1 - 100 of
			// 240)" means there is; "(93 messages)" means that is all of them.
			matcher of = create_matcher("\\(\\d+ - (\\d+) of (\\d+)\\)", page);
			begin = (of.find() && of.group(1).to_int() < of.group(2).to_int()) ? begin + 1 : 0;
		}
	}
	return sent;
}

/*****************************************************
	The scan's own note of who has already had one
*****************************************************/

// WHY THIS EXISTS AT ALL, since the page reads the mailbox live and does not
// use this: without it a scan fetches a profile for every member including the
// ones who already have a package, which after a send is most of the clan. The
// mailbox is two requests for the whole history, so reading it once when a scan
// starts and consulting it on each batch turns dozens of pointless profile
// fetches into two.
//
// SCAN SCRATCH AND NOT A RECORD OF ANYTHING. The page's answer to "who has
// already had one" is always the live mailbox, which is what COwliCK chose
// (2026-11-21); this file only ever decides which profiles are worth fetching.
// Being wrong costs a handful of wasted requests, which is why it is allowed to
// be a week old at all -- and why nothing refuses to work when it is missing.
string CARE_SENT_FILE = "ar_care_sent.txt";

// Plain, not `static`, for the same reason as the two caches above.
int [int] careSentScratch;
boolean careSentScratchLoaded;

void careReadSentScratch() {
	if (careSentScratchLoaded) return;
	careSentScratchLoaded = true;
	file_to_map(CARE_SENT_FILE, careSentScratch);
}

// who -> the epoch seconds it was noted at, so a stale note can be ignored
// rather than trusted forever.
void careSaveSentScratch(boolean [int] who) {
	int [int] fresh;
	int now = now_to_int() / 1000;
	foreach id in who fresh[id] = now;
	careSentScratch = fresh;
	careSentScratchLoaded = true;
	map_to_file(careSentScratch, CARE_SENT_FILE);
}

boolean careScratchSaysSent(int who) {
	careReadSentScratch();
	if (!(careSentScratch contains who)) return false;
	return (now_to_int() / 1000) - careSentScratch[who] < careHoldSeconds();
}

// EVERYTHING A SCAN LEFT BEHIND, forgotten. This is what "look up again" means
// while the held roster is still fresh: without it, pressing it would re-walk
// the roster, find every login still inside the week, fetch nothing, and look
// exactly like a button that does not work.
//
// HERE AND NOT IN THE ENDPOINT, although only the endpoint calls it, because
// the three caches above are this file's business. An endpoint that emptied
// the files and left those in-memory maps holding the old rows would answer
// its own request out of them -- the page would be told the clan still has 239
// members a moment after being told it was cleared.
void careForgetSnapshot() {
	care_saved [int] noRoster;
	careRosterCache = noRoster;
	careRosterLoaded = true;
	map_to_file(careRosterCache, CARE_ROSTER_FILE);

	care_login [int] noLogins;
	careLoginCache = noLogins;
	careLoginsRead = true;
	careLoginsDirty = false;
	map_to_file(careLoginCache, CARE_LOGIN_FILE);

	int [int] noSent;
	careSentScratch = noSent;
	careSentScratchLoaded = true;
	map_to_file(careSentScratch, CARE_SENT_FILE);
}


/*****************************************************
	The plan
*****************************************************/

// Why a member is or is not getting one. Exactly one of these per row, so the
// page can say the reason rather than only showing a shorter list.
string CARE_WOULD    = "would";     // active, no package yet
string CARE_HAD      = "had";       // already in your sent mail
string CARE_QUIET    = "quiet";     // has not logged in within N days
string CARE_INACTIVE = "inactive";  // KoL marks the account inactive
string CARE_PENDING  = "pending";   // not looked up yet: no scan has reached them
string CARE_UNKNOWN  = "unknown";   // looked up, and the profile would not parse
string CARE_SELF     = "self";      // you
string CARE_ASTRAL   = "astral";    // in Valhalla, mid-ascension: no last login exists

record care_row {
	care_member member;
	string verdict;
	string lastLogin;
	int days;
};


// WHETHER THE SEND TICK IS YOURS TO SET, and whether it starts set. COwliCK's
// call, 2026-11-21: the rules become a default you can argue with rather than
// a verdict you cannot.
//
// The split is between a reason that is an OPINION and a reason that is a
// FACT. "Not logged in lately" is this page's own arithmetic against a number
// you chose, and "unreadable" and "not looked up yet" are both just missing
// information -- you may know better than any of them, so they unfold into an
// empty tick you can set.
//
// IN VALHALLA IS ONE OF THOSE, by COwliCK's decision (2026-11-21): "disable
// send to them but with the checkbox we've added they can be sent to." There
// is no last login to judge an astral spirit by and no telling how long they
// have been there, so the page does not pretend to know -- but somebody who
// just ascended is about as alive as a clan member gets, so the tick is right
// there to set.
//
// The three that stay locked are not opinions. You have already sent to them
// (ticking it sends a second), KoL has marked the account inactive, or it is
// you. Nothing you know changes any of those, so the box is not drawn at all
// and the reason stands in its place.
boolean careTickable(string verdict) {
	// ONLY YOURSELF, because that is the only one that is impossible rather
	// than merely unwise: KoL will not let you kmail yourself.
	//
	// It used to lock the inactive and anybody who had already had one too.
	// Those are judgements, and the page now shows the facts behind both --
	// Last Login says how long ago they played, the Packages column says how
	// many they have had and what was in them -- so the box is yours to set
	// and the row beside it is what you set it from. COwliCK, 2026-11-21:
	// "make checkbox and date of login show as much as possible."
	return verdict != CARE_SELF;
}

// Only the one the page is for. Everything else is a tick you have to mean.
boolean careTickedByDefault(string verdict) {
	return verdict == CARE_WOULD && careTickable(verdict);
}

// Every member with a verdict, in roster order.
//
// FETCHES NO PROFILE. It reads the held roster and the held logins off disk and
// the mailbox off KoL, so drawing the page costs the mailbox's two requests and
// nothing else -- where this used to spend eighty profile fetches inside the
// render and leave the rest "pending" with a sentence asking you to reload.
// Everything a member's row needs that is not on disk yet is what the scan is
// for; see ar_care_scan.ash.
//
// THE MAILBOX STAYS LIVE on every load, which is COwliCK's call (2026-11-21):
// the roster and the logins are a week's cache, but who has already had one is
// read fresh every time, because that is the answer whose being stale would
// cost somebody a second package.
//
// Set by carePlan() so the page can tell "your clan is empty" from "no scan has
// run yet", and refuse to send when the mailbox did not come back either. A
// file-scope pair rather than a return value because carePlan already returns
// the rows and ASH has no tuple; read it straight after calling.
boolean careRosterRead = false;
boolean careSentRead = false;

// WHAT THE MAILBOX SAID, kept so the page can draw the Packages column from
// the read carePlan() has already paid for. A second careAlreadySent() would
// be a second walk of the Outbox on every page load, for an answer this one
// already has. Read it straight after calling carePlan(), the same contract
// the two flags above keep.
care_sent careSentRecord;

care_row [int] carePlan() {
	care_sent sent = careAlreadySent();
	careSentRead = sent.read;
	careSentRecord = sent;
	int mine = my_id().to_int();
	int window = careDays();

	care_member [int] roster = careHeldRoster();
	careRosterRead = count(roster) > 0;

	care_row [int] rows;
	foreach i, m in roster {
		care_row r;
		r.member = m;
		r.days = -1;

		// THE LAST LOGIN IS READ FOR EVERYBODY, whatever their verdict turns
		// out to be. It used to be read only inside the final branch, so a
		// member who had already had a package -- or whose account is marked
		// inactive -- showed no date at all even when one was sitting in the
		// cache. COwliCK, 2026-11-21: "make checkbox and date of login show
		// as much as possible."
		care_login seen = careCachedLogin(m.who);
		r.lastLogin = seen.lastLogin;
		r.days = seen.days;

		// Ordered cheapest and most decisive first.
		if (m.who == mine) {
			r.verdict = CARE_SELF;
		} else if (sent.who contains m.who) {
			r.verdict = CARE_HAD;
		} else if (m.inactive) {
			r.verdict = CARE_INACTIVE;
		} else {
			// ASTRAL BEFORE UNREADABLE, because both have days = -1 and only
			// one of them is a failure. An astral spirit's profile came back
			// exactly as KoL meant to send it; there is simply no last login
			// on it, which is a different thing from one we could not read.
			if (!seen.looked)                          r.verdict = CARE_PENDING;
			else if (seen.lastLogin == CARE_ASTRAL_LOGIN) r.verdict = CARE_ASTRAL;
			else if (seen.days < 0)                    r.verdict = CARE_UNKNOWN;
			else if (seen.days > window)               r.verdict = CARE_QUIET;
			else                                       r.verdict = CARE_WOULD;
		}
		rows[count(rows)] = r;
	}
	// No careSaveLogins() here any more, and its absence is the change: this
	// function no longer writes anything, because it no longer fetches
	// anything. The scan saves what it fetches.
	return rows;
}

// WHO A SCAN STILL OWES A PROFILE FETCH, in roster order.
//
// Worked out fresh on every call from the held roster and the current
// preferences, rather than frozen into the snapshot when the scan started. That
// matters for one case that would otherwise look broken: un-skip a rank, and
// those members become people the page says it has not looked up -- so the
// to-do count has to agree, or the button offers nothing to do above a list of
// rows saying "not looked up yet".
//
// The mailbox is consulted through the scratch note rather than read, because
// this is called on every page load and the whole point is that a page load
// costs no requests beyond the one mailbox read carePlan already does. Being
// wrong here costs a few wasted profile fetches and nothing else.
int [int] careScanQueue() {
	int mine = my_id().to_int();
	int [int] queue;
	// EVERYBODY BUT YOU. It used to skip the inactive and anybody the scan
	// had noted as already sent to, which saved their profile fetch -- and
	// cost them a last login, so those rows had no date to show however
	// recently they had played. The saving was about twenty requests out of
	// two hundred and forty; the column it emptied is one of four.
	foreach i, m in careHeldRoster() {
		if (m.who == mine) continue;
		if (!careLoginNeeded(m.who)) continue;
		queue[count(queue)] = m.who;
	}
	return queue;
}

int careScanTodo() { return count(careScanQueue()); }


int careCount(care_row [int] rows, string verdict) {
	int n = 0;
	foreach i, r in rows if (r.verdict == verdict) n = n + 1;
	return n;
}

/*****************************************************
	What the package is, and whether it can be sent
*****************************************************/

record care_problem {
	string what;
	boolean fatal;
};

// Everything wrong with the configured package, each named. Checked here rather
// than at send time so the page can refuse to offer a button at all, which is
// the only refusal that cannot be clicked past.
care_problem [int] carePackageProblems() {
	care_problem [int] found;
	arLimits limits = arLimitsNow();
	void note(string what, boolean fatal) {
		care_problem p;
		p.what = what;
		p.fatal = fatal;
		found[count(found)] = p;
	}

	// Said first, because it is the one problem that is not about the package:
	// without your sent mail there is no way to tell who already has one, and
	// sending on that basis would send to everybody twice.
	if (!careSentRead) {
		note("Could not read your sent mail, so there is no telling who has already"
			+ " had a package. KoLmafia may have been busy; reload the page.", true);
	}
	// STILL FATAL, BUT NO LONGER AN ERROR. There is nobody to send to without a
	// roster, so a send must still be refused -- but the reason changed when
	// the roster stopped being fetched per page load: an empty one used to mean
	// the request had failed, and now means no scan has run yet, which is what
	// a fresh install looks like. Telling somebody KoLmafia was busy when they
	// have simply not pressed the button yet sends them to look for a fault
	// that is not there.
	if (!careRosterRead) {
		note("No clan roster is held yet, so there is nobody to send to."
			+ " Press <b>Look up clan members</b>.", true);
	}

	string list = carePackage();
	if (list == "" && careMeat() <= 0) {
		// Points at the box now rather than at the gCLI, which is where this
		// had to send you until the Package box existed.
		note("Nothing in the package yet. Name an item or some Meat in"
			+ " <b>Package</b> and this page will offer to send it.", true);
		return found;
	}

	care_part [int] parts = carePackageParts(list);
	int items = count(parts);
	foreach i, p in parts {
		if (p.what == $item[none]) {
			note("No such item: \"" + p.named + "\".", true);
			continue;
		}
		// is_giftable() is the one thing ASH knows about sending. A bound item
		// cannot leave, gift box or not, so this is fatal rather than a warning.
		if (!p.what.is_giftable()) {
			note(p.what + " cannot be sent to anyone.", true);
			continue;
		}
		int held = careReachable(p.what, limits);
		if (held < p.qty) {
			note("The places you allow hold " + held + " " + p.what
				+ ", and the package wants " + p.qty + ".", false);
		}
	}

	// KoLmafia picks the gift box itself and its pick is capped at the sixth
	// one, the miniature coffin, which holds 5 (SendMessageCommand.send:
	// min(min(size-1, attachments), 5)). A package of more than five distinct
	// items therefore cannot be auto-gifted -- and a gift box is exactly what a
	// recipient in Hardcore or Ronin needs -- so this is refused rather than
	// sent as something that works for some of the clan and not others.
	if (items > 5) {
		note("The package has " + items + " different items. KoLmafia's gift box holds 5,"
			+ " and anyone in Hardcore or Ronin can only be sent a gift box.", true);
	}

	return found;
}

boolean careSendable(care_problem [int] problems) {
	foreach i, p in problems if (p.fatal) return false;
	return true;
}
