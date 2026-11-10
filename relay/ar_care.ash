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
//                     the expensive part, so it is cached on disk and spent
//                     from a per-load budget.
//   who already had   messages.php, TWO requests for the whole history. See
//                     careAlreadySent().

// Shares this repository's own item sourcing with the anti-raffle: where a
// thing may be taken from, whether that place will hand it over today, and how
// many are there. An anti-raffle restocking its tickets and a care package
// being packed are the same question, so they ask it the same way rather than
// each keeping an answer.
import <ar_core.ash>

/*****************************************************
	Preferences
*****************************************************/

// Named the way this repository names its own (arTicketItems, arRestockCount).
// The prefix is not decoration: KoLmafia preferences are one namespace shared
// with every script installed, the same way relay/ and scripts/ are, and so is
// the data/ folder the cache below sits in.
//
// Set them with KoLmafia's `set`, or from Preferences in the Swing client.
// Nothing here writes a preference -- the page only reads -- so there is no
// settings endpoint to allowlist them in, the way ar_prefs.ash does for the
// three the anti-raffle page can change.
string CARE_DAYS    = "arCareDays";
string CARE_PACKAGE = "arCarePackage";
string CARE_MEAT    = "arCareMeat";
string CARE_SOURCES  = "arCareSources";
string CARE_NOTE    = "arCareNote";
string CARE_SKIP    = "arCareSkipRanks";

int CARE_DAYS_FALLBACK = 14;

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

// Where a package may be packed from, as a set of this repository's own source
// names (ar_core.ash: inventory, closet, display, storage). Unset means all of
// them, which is what the anti-raffle's AR_SOURCES_DEFAULT means too.
//
// ITS OWN PREFERENCE RATHER THAN arSources, although the names and the
// validation are shared. Giving a hundred people a package and keeping a
// store stocked are different decisions -- storage is a Ronin pull each, and
// you might well spend those on one and not the other -- so they share the
// code and not the setting.
boolean [string] careSources() {
	boolean [string] on;
	string raw = get_property(CARE_SOURCES);
	if (raw == "") raw = AR_SOURCES_DEFAULT;

	foreach i, piece in raw.split_string(",") {
		string place = piece;
		while (place.starts_with(" ")) place = place.substring(1, place.length());
		while (place.ends_with(" ")) place = place.substring(0, place.length() - 1);
		if (arIsSource(place)) on[place] = true;
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
	foreach i, place in arAllSources() {
		if (!(on contains place)) continue;
		if (arShutBecause(place, l) != "") continue;
		total = total + arAvailable(it, place);
	}
	return total;
}

string careNote() {
	string s = get_property(CARE_NOTE);
	return s == "" ? "A care package from your clan. Enjoy!" : s;
}

// The ranks not to send to, as a set keyed by the lower-cased rank.
//
// MATCHED WHOLE AND NOT AS A SUBSTRING, which matters on a real roster: a clan
// that has both "Member" and "Senior Member" as ranks would have the second
// quietly taken away with the first. Case is ignored and surrounding spaces are
// trimmed, because the list is typed by hand and "Recruit, Bot" should work.
boolean [string] careSkipRanks() {
	boolean [string] skip;
	foreach i, part in split_string(get_property(CARE_SKIP), ",") {
		string rank = part;
		while (rank.starts_with(" ")) rank = rank.substring(1, rank.length());
		while (rank.ends_with(" ")) rank = rank.substring(0, rank.length() - 1);
		if (rank != "") skip[rank.to_lower_case()] = true;
	}
	return skip;
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

// Twelve hours.
//
// A DELIBERATE DEPARTURE from this repo's cache-stamp convention, which is "a
// stamp of what the answer depends on" rather than a clock
// -- because another player's last login depends on nothing this character
// can observe. A clock is the only
// stamp available, so the question is only how stale is tolerable: an N-day
// window decided on week-old data silently drops people who have come back,
// which is the failure that matters here.
int CARE_LOGIN_TTL = 12 * 60 * 60;

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

// Read once per interpreter and saved only if something changed. A relay
// script gets a fresh interpreter per request, so `static` is a cache across
// the rows of one page load and the file is the cache across page loads.
static {
	care_login [int] careLoginCache;
	boolean careLoginsRead;
	boolean careLoginsDirty;
}

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

// A member's last login, from the cache when it is fresh and from their profile
// when it is not. Spends one request from `budget` and answers an empty record
// when the budget is gone, so a first load on a big clan comes back as a page
// with some rows unknown rather than not at all.
care_login careLastLogin(int who, int [int] budget) {
	careReadLogins();

	int now = now_to_int() / 1000;
	if (careLoginCache contains who && now - careLoginCache[who].fetchedAt < CARE_LOGIN_TTL) {
		return careLoginCache[who];
	}

	care_login notyet;
	notyet.days = -1;
	notyet.format = CARE_LOGIN_FORMAT;
	notyet.looked = false;
	if (budget[0] < 1) return notyet;
	budget[0] = budget[0] - 1;

	string page = visit_url("showplayer.php?who=" + who);

	care_login entry;
	entry.lastLogin = careParseLastLogin(page);
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
record care_sent {
	boolean read;
	boolean [int] who;
};

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
		if (to.find()) sent.who[to.group(1).to_int()] = true;
	}
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
	The plan
*****************************************************/

// Why a member is or is not getting one. Exactly one of these per row, so the
// page can say the reason rather than only showing a shorter list.
string CARE_WOULD    = "would";     // active, no package yet
string CARE_HAD      = "had";       // already in your sent mail
string CARE_QUIET    = "quiet";     // has not logged in within N days
string CARE_INACTIVE = "inactive";  // KoL marks the account inactive
string CARE_SKIPPED  = "skipped";   // their rank is in careSkipRanks
string CARE_PENDING  = "pending";   // not looked up yet: the budget ran out
string CARE_UNKNOWN  = "unknown";   // looked up, and the profile would not parse
string CARE_SELF     = "self";      // you

record care_row {
	care_member member;
	string verdict;
	string lastLogin;
	int days;
};

// Every member with a verdict, in roster order. `budget` is spent on the
// profiles; pass it by reference as an int[int] because ASH passes an aggregate
// by reference and an int by value, and every row has to draw on the one
// budget.
// Set by carePlan() so the page can tell "your clan is empty" from "the roster
// did not come back", and refuse to send when the mailbox did not either. A
// file-scope pair rather than a return value because carePlan already returns
// the rows and ASH has no tuple; read it straight after calling.
boolean careRosterRead = false;
boolean careSentRead = false;

care_row [int] carePlan(int [int] budget) {
	care_sent sent = careAlreadySent();
	careSentRead = sent.read;
	int mine = my_id().to_int();
	int window = careDays();
	boolean [string] skip = careSkipRanks();

	care_member [int] roster = careRoster();
	careRosterRead = count(roster) > 0;

	care_row [int] rows;
	foreach i, m in roster {
		care_row r;
		r.member = m;
		r.days = -1;

		// Ordered cheapest and most decisive first: everything down to the
		// inactive check costs no request at all, so only the members who might
		// actually get a package are ever looked up.
		//
		// A skipped rank comes before "already had one" deliberately. Both are
		// free, but the question this page answers is who would get one NOW,
		// and a rank you have excluded is excluded whatever their history.
		if (m.who == mine) {
			r.verdict = CARE_SELF;
		} else if (skip contains m.rank.to_lower_case()) {
			r.verdict = CARE_SKIPPED;
		} else if (sent.who contains m.who) {
			// Both of these are decided before any profile is fetched, so
			// somebody who already has one -- or whose account KoL has already
			// told us is inactive -- costs no request at all.
			r.verdict = CARE_HAD;
		} else if (m.inactive) {
			r.verdict = CARE_INACTIVE;
		} else {
			care_login seen = careLastLogin(m.who, budget);
			r.lastLogin = seen.lastLogin;
			r.days = seen.days;
			if (!seen.looked)             r.verdict = CARE_PENDING;
			else if (seen.days < 0)       r.verdict = CARE_UNKNOWN;
			else if (seen.days > window)  r.verdict = CARE_QUIET;
			else                          r.verdict = CARE_WOULD;
		}
		rows[count(rows)] = r;
	}
	careSaveLogins();
	return rows;
}

// Every rank on the roster and how many hold it, so the page can show what
// there is to skip. Without this the setting is unusable without going and
// reading three pages of roster to find out how a rank is spelled.
int [string] careRankCounts(care_row [int] rows) {
	int [string] counts;
	foreach i, r in rows {
		string rank = r.member.rank == "" ? "(no rank)" : r.member.rank;
		counts[rank] = (counts contains rank ? counts[rank] : 0) + 1;
	}
	return counts;
}

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
	if (!careRosterRead) {
		note("Could not read the clan roster. KoLmafia may have been busy;"
			+ " reload the page.", true);
	}

	string list = carePackage();
	if (list == "" && careMeat() <= 0) {
		note("No package set yet. Set " + CARE_PACKAGE + " (and/or " + CARE_MEAT
			+ ") and this page will offer to send it. From the gCLI:"
			+ " <code>set arCarePackage = 3 soda water</code>.", true);
		return found;
	}

	int items = 0;
	foreach i, part in split_string(list, ",") {
		string want = part;
		while (want.starts_with(" ")) want = want.substring(1, want.length());
		while (want.ends_with(" ")) want = want.substring(0, want.length() - 1);
		if (want == "") continue;
		items = items + 1;

		// KoLmafia's own item-list syntax, so "3 soda water" is one entry.
		// to_item of a leading count does not resolve, so the count comes off
		// first.
		matcher counted = create_matcher("^(\\d+)\\s+(.*)$", want);
		int qty = 1;
		string named = want;
		if (counted.find()) {
			qty = counted.group(1).to_int();
			named = counted.group(2);
		}

		item it = named.to_item();
		if (it == $item[none]) {
			note("No such item: \"" + named + "\".", true);
			continue;
		}
		// is_giftable() is the one thing ASH knows about sending. A bound item
		// cannot leave, gift box or not, so this is fatal rather than a warning.
		if (!it.is_giftable()) {
			note(it + " cannot be sent to anyone.", true);
			continue;
		}
		int held = careReachable(it, limits);
		if (held < qty) {
			note("The places you allow hold " + held + " " + it
				+ ", and the package wants " + qty + ".", false);
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
