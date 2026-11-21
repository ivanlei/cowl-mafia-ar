// ar_care_send.ash -- sends the package, a few recipients per request.
//
//     ?to=<id>,<id>,<id>    send to these, and report what happened to each
//
// THE ONLY THING IN THIS REPOSITORY THAT SENDS ANYTHING. Everything else
// here reads: the roster, the profiles, the mailbox. This mails real people
// real items and there is no unsend, so the rules it keeps are worth saying
// in one place.
//
// IT SENDS TO WHO IT IS TOLD, AND CHECKS EACH ONE ANYWAY. The browser has
// the ticks and the browser names the recipients, but a page is not a
// permission: every id is checked against the held roster, against the
// mailbox note of who has already had one, and against being you, before
// anything is sent to it. A tick on a row is a request, not an authority.
//
// A FEW AT A TIME, like the scan and for the same reasons: 190 sends is
// minutes of requests, and a browser that gets an answer every few seconds
// can show a progress line, offer a Stop, and survive a closed tab with the
// half of the job that is done still done.
//
// WHAT "DONE" MEANS IS THE MAILBOX, not a list of ours. careAlreadySent()
// reads your own sent mail for the marker, which is the one record that
// cannot disagree with the game -- so a send interrupted anywhere, by a
// Stop, a crash or a closed laptop, resumes correctly because the question
// "has this person had one" is asked of KoL and not of a file.

import <ar_care.ash>
import <ar_relay.ash>

// How many to send to in one request. Smaller than the scan's batch: a send
// is a kmail and possibly a gift box, which is two requests to KoL rather
// than one, and the point of a batch is that the page hears back often.
int CARE_SEND_BATCH = 3;

record care_sent_one {
	int who;
	string name;
	boolean sent;
	boolean had;     // refused because they already have one, which is not a failure
	string why;      // empty when it went
};

// WHY csend AND NOT send. KoLmafia's csend tries a plain kmail first and
// falls back to a gift box when KoL refuses one -- which is what happens for
// a recipient in Hardcore or Ronin -- and it picks the box itself, capped at
// the sixth (SendMessageCommand.send: min(min(packages-1, attachments), 5)).
// That cap is also why careBadValue() refuses a sixth item: a package of more
// than five could not be auto-gifted and would work for part of a clan and
// not the rest.
//
// csend is also the only one of the two that will carry Meat; plain send
// refuses it outright and says so.
//
// THE BODY IS careBody() AND NOT careNote(), which is the difference between
// a package this page can recognise later and one it cannot. careBody()
// appends CARE_MARK, and dedup works by reading your Outbox for exactly that
// marker -- so a package sent without it is invisible to "who has already
// had one" and the next run sends that person a second one.
//
// The first version of this file passed the bare note. Three real test
// packages went out unmarked before it was caught, and the page went on
// offering to send all three again. The library already had careBody(), with
// a comment saying what it was for.
//
// Its marker sits on its own line after a blank one, and that survives the
// trip: cli_execute hands the whole string to one command line without
// splitting it, and csend takes everything after the || and only trims the
// ends (SendMessageCommand.send).
string careSendCommand(string recipient, care_part [int] parts, int meat, string body) {
	buffer cmd;
	cmd.append("csend ");
	boolean first = true;
	foreach i, p in parts {
		if (!first) cmd.append(", ");
		first = false;
		cmd.append(p.qty + " " + carePackageTerm(p));
	}
	if (meat > 0) {
		if (!first) cmd.append(", ");
		first = false;
		cmd.append(meat + " meat");
	}
	cmd.append(" to " + recipient);
	cmd.append(" || " + body);
	return cmd.to_string();
}

// Whether a send actually happened, which cli_execute cannot tell us.
//
// A REFUSED COMMAND STILL RETURNS true from cli_execute when KoLmafia logs
// the refusal as a warning rather than an error, so its return value is not
// the answer. What is the answer is the mailbox: careLooksLikeSent() asks
// KoL whether the message is in your Outbox, which is the same question the
// page asks to know who has already had one, so the two cannot disagree.
//
// One mailbox read per batch rather than per recipient -- the Outbox's first
// page holds far more than a batch -- which is why this takes the set.
boolean [int] careWhoGotOne() {
	care_sent sent = careAlreadySent();
	if (!sent.read) {
		boolean [int] none;
		return none;
	}
	return sent.who;
}

// WHAT THE PACKAGE IS PACKED FROM, actually done rather than merely counted.
//
// THE BUG THIS IS FOR, and it is the worst one this page has had. The Config
// box says "Gather Items From: Inventory, Closet, Display Case", and
// careReachable() counts all three -- but KoLmafia's csend attaches from the
// INVENTORY and nowhere else (SendMessageCommand: getMatchingItemList(itemList,
// KoLConstants.inventory)). An item in the display case therefore matched
// nothing, and because the OTHER item in the package did match,
// attachments.length was not zero and the send went ahead with what it had.
//
// COwliCK sent sixty-nine people a package of "1 R'lyeh, 1 11-leaf clover"
// with 365 R'lyeh in his display case and none in his inventory. Every one of
// the sixty-nine arrived holding a clover. The session log says so in plain
// sight -- "send a kmail to <name>: 1 11-leaf clover, 11 Meat" -- and nothing
// anywhere said a word about the missing half.
//
// So the places are gathered from for real: the closet first, because taking
// from it costs nothing at all, then the display case, which is a request to
// KoL and is shut in Ronin (arShutBecause). Hagnk's is not a source here and
// never will be -- a pull costs one of the day's twenty.
//
// Enough for the whole batch in one go rather than one recipient at a time:
// take_display() is a KoL request either way, so three at once is two requests
// saved and nothing lost.
void careStock(care_part [int] parts, int people, arLimits limits) {
	boolean [string] on = careSources();
	foreach i, p in parts {
		if (p.what == $item[none]) continue;
		int want = p.qty * people;

		if (on contains "closet") {
			int missing = want - item_amount(p.what);
			int there = closet_amount(p.what);
			if (missing > 0 && there > 0) {
				take_closet(missing < there ? missing : there, p.what);
			}
		}

		if ((on contains "display") && arShutBecause("display", limits) == "") {
			int missing = want - item_amount(p.what);
			int there = display_amount(p.what);
			if (missing > 0 && there > 0) {
				take_display(missing < there ? missing : there, p.what);
			}
		}
	}
}

void main() {
	if (!arAuthorised()) {
		arRefuseStale();
		return;
	}

	// NOTHING IS SENT WITHOUT ALL THREE, checked here and not only in the
	// page: the button is disabled without them, and a disabled button is a
	// courtesy rather than a guard.
	care_part [int] parts = carePackageParts(carePackage());
	int meat = careMeat();
	string note = careNote();
	if (count(parts) == 0 && meat <= 0) {
		arRefuse("There is nothing in the package.");
		return;
	}
	if (note == "") {
		arRefuse("The package has no note.");
		return;
	}

	// THE SAME RULE THE SAVE KEEPS, asked again of what is stored: every item
	// real, every one giftable, no more than the five a gift box holds. The
	// Package box cannot write a package that fails this, but the gCLI can,
	// and `set arCarePackage = 6 things` must not become six things sent to
	// two hundred people.
	string wrong = careBadValue(CARE_PACKAGE, carePackage());
	if (wrong != "") {
		arRefuse(wrong);
		return;
	}

	// NOT carePackageProblems(), which was the first version of this check
	// and refused everything: it reports on careRosterRead and careSentRead,
	// and those are set by carePlan() -- which the page calls and this
	// endpoint has no reason to. Both were still false here, so every send
	// was refused as "the package cannot be sent as it stands".
	//
	// What that check was really for is the one below, and it is the single
	// most important line in this file.

	// THE MAILBOX MUST BE READABLE OR NOTHING IS SENT. careAlreadySent()
	// answers an unreadable Outbox the same way it answers an empty one --
	// with nobody in it -- and "nobody has had one" is precisely the answer
	// that would send a second package to the entire clan. So a failed read
	// is a refusal, never a send.
	care_sent sent = careAlreadySent();
	if (!sent.read) {
		arRefuse("Could not read your sent mail, so there is no telling who has"
			+ " already had one. Nothing was sent. Try again in a moment.");
		return;
	}

	// Who the browser asked for, in the order it asked.
	int [int] asked;
	foreach i, piece in form_field("to").split_string(",") {
		if (piece == "" || !piece.is_integer()) continue;
		asked[count(asked)] = piece.to_int();
	}
	if (count(asked) == 0) {
		arRefuse("Nobody was named.");
		return;
	}

	// The held roster, by id, so a name can be put to each one and anybody
	// who is not in the clan is refused rather than mailed.
	care_member [int] roster = careHeldRoster();
	care_member [int] byId;
	foreach i, m in roster byId[m.who] = m;

	boolean [int] already = sent.who;
	int mine = my_id().to_int();

	// WHO IS ACTUALLY BEING SENT TO, decided before anything is fetched or
	// sent. Two passes rather than one, and the reason is careStock() below:
	// taking things out of a display case to pack packages that were never
	// going to be packed is a real cost to somebody's display case. Pressing
	// Send a second time, where everybody named has already had one, must
	// touch nothing at all.
	care_sent_one [int] done;
	boolean [int] willSend;
	foreach i, who in asked {
		if (count(done) >= CARE_SEND_BATCH) break;

		care_sent_one one;
		one.who = who;
		one.sent = false;
		one.had = false;

		if (!(byId contains who)) {
			one.name = "#" + who;
			one.why = "not on the held roster";
		} else {
			one.name = byId[who].name;
			if (who == mine) {
				one.why = "that is you";
			} else if (already contains who) {
				// THE ONE THAT MATTERS. Read fresh from the Outbox at the
				// start of this request, so a batch cannot send a second
				// package to somebody an earlier batch already reached.
				//
				// SAID AS ITS OWN OUTCOME rather than left for the page to
				// recognise by its sentence. It is not a failure and the page
				// must not colour it as one -- which matters most when a batch
				// is retried after a momentary error, since everybody the first
				// attempt did reach comes back exactly like this and would
				// otherwise be reported as refused.
				one.had = true;
				one.why = "already had one";
			} else {
				willSend[count(done)] = true;
			}
		}
		done[count(done)] = one;
	}

	// EVERYTHING THOSE PACKAGES NEED, OUT OF THE PLACES YOU ALLOW. See
	// careStock() for the sixty-nine half-empty packages that paid for this.
	careStock(parts, count(willSend), arLimitsNow());

	int sentNow = 0;
	foreach i, one in done {
		if (!(willSend contains i)) continue;

		// NO HALF PACKAGES. csend attaches whatever it can find and sends the
		// rest regardless, so the only place this can be stopped is here,
		// before it is asked. Refusing one recipient costs one recipient; the
		// browser names them and carries on to everybody else.
		string short = careShortOf(parts);
		if (short != "") {
			done[i].why = short;
			continue;
		}
		cli_execute(careSendCommand(one.name, parts, meat, careBody()));
		sentNow = sentNow + 1;
	}

	// ASKED AFTER THE BATCH, not after each send: the Outbox is one request
	// and it answers for every name in the batch at once. Anybody who is in
	// it now and was not before went.
	if (sentNow > 0) {
		boolean [int] nowSent = careWhoGotOne();
		foreach i, one in done {
			if (one.why != "") continue;
			if (nowSent contains one.who) {
				done[i].sent = true;
			} else {
				done[i].why = "KoL did not take it";
			}
		}
	}

	buffer out;
	out.append("{\"ok\":true,\"error\":\"\",\"done\":[");
	foreach i, one in done {
		if (i > 0) out.append(",");
		out.append("{\"who\":" + one.who);
		out.append(",\"name\":" + arQuoted(one.name));
		out.append(",\"sent\":" + (one.sent ? "true" : "false"));
		out.append(",\"had\":" + (one.had ? "true" : "false"));
		out.append(",\"why\":" + arQuoted(one.why) + "}");
	}
	out.append("],\"batch\":" + CARE_SEND_BATCH + "}");
	out.write();
}
