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
string careSendCommand(string recipient, care_part [int] parts, int meat, string note) {
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
	cmd.append(" || " + note);
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

	care_problem [int] problems = carePackageProblems();
	if (!careSendable(problems)) {
		// The same refusal the page draws at the top of itself, so a button
		// pressed against a package that cannot be sent says the same thing
		// the list above it already says.
		arRefuse("The package cannot be sent as it stands. See the page.");
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

	boolean [int] already = careWhoGotOne();
	int mine = my_id().to_int();

	care_sent_one [int] done;
	int sentNow = 0;
	foreach i, who in asked {
		if (count(done) >= CARE_SEND_BATCH) break;

		care_sent_one one;
		one.who = who;
		one.sent = false;

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
				one.why = "already had one";
			} else {
				cli_execute(careSendCommand(one.name, parts, meat, note));
				sentNow = sentNow + 1;
			}
		}
		done[count(done)] = one;
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
		out.append(",\"why\":" + arQuoted(one.why) + "}");
	}
	out.append("],\"batch\":" + CARE_SEND_BATCH + "}");
	out.write();
}
