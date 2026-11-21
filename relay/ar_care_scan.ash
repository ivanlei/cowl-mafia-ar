// ar_care_scan.ash -- the Care Packages page's look-up, done a batch at a time
// so that the page can show it happening.
//
//     ?state=1         what there is to do, fetching nothing
//     ?roster=1        walk clan_members.php, replace the held roster
//     ?step=1          fetch the next careScanBatch() profiles
//     ?clear=1         forget the held roster, logins and sent note
//
// WHY A BATCH AT A TIME, rather than one request that does the lot. A clan of
// 216 is 216 profile fetches at about 100ms each, and the page that used to do
// them inside its own render showed nothing for eight seconds and then gave up
// with two thirds of the clan still unread. One request per batch means the
// browser gets an answer every second or so, which is what lets it draw a
// progress line, lets a Stop button work, and lets a closed tab leave the scan
// half-done rather than lost -- the next press picks up where it stopped,
// because what is done is on disk and not in a loop's local variable.
//
// IT FETCHES ONLY WHAT IT STILL OWES. careScanQueue() is the one definition of
// that (ar_care.ash), shared with the page's button label and this file's
// counts, so the number the page shows and the number this works through cannot
// drift apart.
//
// NOTHING HERE SENDS ANYTHING. It reads the roster, profiles and the mailbox.
// There is no send endpoint in this repository at all.

import <ar_care.ash>
import <ar_relay.ash>

// What every path answers with, so the page has one shape to read:
//
//   total   members in the held roster
//   todo    how many still need a profile fetch
//   done    total minus todo, for a progress line
//   at      when the held roster was taken, epoch seconds, or 0 for "no scan"
//   batch   how many a ?step fetches, so the page can pace itself
//   pause   ms the page should wait between batches
//   held    how many days a scan is kept, for the page's header
string careScanJson(string extra) {
	int total = count(careHeldRoster());
	int todo = careScanTodo();

	buffer out;
	out.append("{\"ok\":true,\"error\":\"\"");
	out.append(",\"total\":" + total);
	out.append(",\"todo\":" + todo);
	out.append(",\"done\":" + (total - todo));
	out.append(",\"at\":" + careSnapshotAt());
	out.append(",\"batch\":" + careScanBatch());
	out.append(",\"pause\":" + careScanPause());
	out.append(",\"held\":" + careHoldDays());
	if (extra != "") out.append("," + extra);
	out.append("}");
	return out.to_string();
}

// The roster, and the mailbox note that keeps the scan off profiles it does not
// need. Both at the start of a scan, because both are cheap for the whole clan
// (three requests and two) where a profile is one request per member.
//
// THE ROSTER IS NOT REPLACED WITH NOTHING. An empty walk is what a request
// landing while the gCLI is busy looks like -- KoLmafia serializes its requests
// and answers the loser with an empty page -- and taking that as the new roster
// would throw away a perfectly good snapshot and report a clan of zero. So an
// empty answer is refused and the held roster is left exactly as it was.
void careScanRoster() {
	care_member [int] roster = careRoster();
	if (count(roster) == 0) {
		arRefuse("The clan roster did not come back. Nothing was changed.");
		return;
	}
	careSaveRoster(roster);

	// The mailbox note is best-effort BY DESIGN. If it does not come back the
	// scan simply fetches a few profiles it need not have, which costs requests
	// and nothing else -- so an unread mailbox must not stop a scan here, where
	// the page's own live read is what decides anything.
	care_sent sent = careAlreadySent();
	if (sent.read) careSaveSentScratch(sent.who);

	write(careScanJson("\"rostered\":" + count(roster)
		+ ",\"sentRead\":" + (sent.read ? "true" : "false")));
}

// One batch. Walks the queue in roster order and spends the batch on it, so
// two presses in a row do not fetch the same member twice: what the first one
// fetched is on disk before this answers, and careScanQueue() reads disk.
void careScanStep() {
	int [int] queue = careScanQueue();
	if (count(queue) == 0) {
		write(careScanJson("\"fetched\":0"));
		return;
	}

	int [int] budget;
	budget[0] = careScanBatch();

	int fetched = 0;
	foreach i, who in queue {
		if (budget[0] < 1) break;
		care_login got = careLastLogin(who, budget);
		if (got.looked) fetched = fetched + 1;
	}
	// Once for the batch rather than once per profile: map_to_file rewrites the
	// whole file, and doing that per member turns a 216-member scan into 216
	// rewrites of a growing file.
	careSaveLogins();

	write(careScanJson("\"fetched\":" + fetched));
}

// Start again from nothing. This is what "look up again" means when the held
// roster is still fresh: without it, a scan would re-walk the roster and then
// find every login fresh and fetch nothing, which looks exactly like the button
// not working.
void careScanClear() {
	careForgetSnapshot();
	write(careScanJson("\"cleared\":true"));
}

void main() {
	if (!arAuthorised()) {
		arRefuseStale();
		return;
	}

	if (form_field("clear") != "")  { careScanClear();  return; }
	if (form_field("roster") != "") { careScanRoster(); return; }
	if (form_field("step") != "")   { careScanStep();   return; }

	// ?state=1, and anything that names nothing: the counts, having fetched
	// nothing. The page asks for this on load to label its button.
	write(careScanJson(""));
}
