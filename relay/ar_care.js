// ar_care.js -- the Care Packages page's three moving parts: the look-up
// button, the Config box's save-on-change, and the ticked count.
//
// The page is server-rendered and means to stay that way, so the test for
// whether something belongs in here is narrow: it has to be a thing the
// server cannot answer. Driving a scan the page wants to watch happen,
// writing a setting without a round trip per keystroke, and following ticks
// that exist only in this browser all pass it. Anything else -- a verdict, a
// count of the roster, the price of a send -- is written in ASH, and the
// moment a number is written twice is the moment the two copies start to
// disagree.
//
// WHAT IT IS FOR. Working out who in the clan is active costs one profile
// request per member, and on a clan of a couple of hundred that is a minute or
// so of requests however it is arranged. The page used to spend it inside its
// own render -- eighty profiles, about eight seconds of a blank browser, and
// then a sentence asking you to reload for the next eighty. COwliCK,
// 2026-11-21: "it started loading profiles when the page loaded, stopped
// midway, didn't well indicate what it was doing."
//
// So nothing is fetched until this asks for it: a press starts the scan, one
// batch per request (ar_care_scan.ash), with a pause between batches, the
// buttons disabled while it runs, and a line saying how far it has got.
//
// IT RELOADS THE PAGE WHEN IT FINISHES, rather than redrawing the table. The
// table is a hundred lines of server-side ASH with eight verdict sections and
// a summary that prices the whole send; a second renderer here would be the
// thing that disagrees with it. Stopping reloads too, for the same reason --
// the button labels and the counts are the page's to write, and there is one
// place that writes them.
//
// THE DECISIONS ARE PURE AND THE REST IS DOM, with the module.exports hatch
// below the first group. .github/check.py runs tests/*.test.js with a plain
// `node <file>`, so anything reachable from there is a thing a test can hold
// still -- and the loop's stopping rules are exactly what wants holding still:
// a scan that never stops hammers KoL, and one that stops early looks like it
// worked.

(function () {
	'use strict';

	// WHAT A BATCH COSTS, measured rather than assumed: a profile fetch is
	// about 100ms of KoL's own latency (which is where the old page's "80 is
	// about eight seconds" came from). Used only until the scan has timed a
	// batch of its own, after which the estimate is the observed rate.
	var PROFILE_MS = 100;

	// Whether to ask for another batch, and if not, why not. The four answers
	// are the whole control flow:
	//
	//   go        ask for another batch
	//   done      nothing left to look up
	//   stopped   the Stop button was pressed
	//   stalled   a batch came back having fetched nothing while work remained
	//
	// STALLED IS THE IMPORTANT ONE. A profile request that does not bring back
	// a profile is deliberately not cached (careLooksLikeProfile in
	// ar_care.ash), so the member stays in the queue -- which means a KoL that
	// has stopped answering would otherwise be asked for the same five
	// profiles for ever, by a loop nobody is watching. No progress is the
	// signal to stop.
	function careScanNext(state) {
		if (state.stopped) return 'stopped';
		if (state.todo <= 0) return 'done';
		// Before the first batch there is nothing to have made progress on.
		if (state.fetched === null || state.fetched === undefined) return 'go';
		if (state.fetched <= 0) return 'stalled';
		return 'go';
	}

	// Seconds still to go, from what this scan has actually cost so far: the
	// elapsed time over the profiles fetched, times what is left, plus a pause
	// per remaining batch. Falls back to PROFILE_MS before anything has been
	// fetched.
	//
	// Rounded up and never negative, because this is drawn as "about N
	// seconds left" and "about 0 seconds left" for several seconds is how a
	// progress line loses the reader's trust.
	// THE PAUSE IS COUNTED ONCE, which the first version of this got wrong and
	// a live scan showed up at once: it said "about 86 seconds left" at a
	// moment when 50 were left, every time, high by about the ratio you would
	// expect. Elapsed time already spans the pauses, so adding a pause per
	// remaining batch on top of an observed rate charges for them twice.
	//
	// So the two branches are both "ms per profile, pauses included": measured
	// when there is a measurement, and otherwise the profile's own ~100ms plus
	// that profile's share of its batch's pause.
	function careEta(state) {
		var todo = Math.max(0, state.todo);
		if (todo === 0) return 0;

		var batch = state.batch > 0 ? state.batch : 1;
		var each = state.fetchedSoFar > 0 && state.elapsedMs > 0
			? state.elapsedMs / state.fetchedSoFar
			: PROFILE_MS + Math.max(0, state.pause || 0) / batch;
		return Math.ceil(todo * each / 1000);
	}

	// "looked up 85 of 193 · about 45 seconds left", or the shorter sentence
	// when there is no estimate worth giving.
	//
	// COUNTED AGAINST WHAT THIS SCAN OWES, not against the clan. The first
	// version used the endpoint's `done`, which is the roster minus the queue
	// -- so it opened a fresh scan with "looked up 26 of 239" a second and a
	// half in, having looked up nothing: those 26 were you, the inactive
	// accounts and anyone already sent to, none of whom is ever fetched. A
	// progress line that starts by claiming work it did not do is worse than
	// no progress line.
	function careProgressText(state) {
		var fetched = state.fetchedSoFar || 0;
		var line = 'looked up ' + fetched + ' of ' + (fetched + Math.max(0, state.todo));
		var left = careEta(state);
		if (state.todo > 0 && left > 0) {
			line += ' · about ' + left + (left === 1 ? ' second left' : ' seconds left');
		}
		return line;
	}

	// "191 of 218 ticked", over the table.
	//
	// THE DENOMINATOR IS WHO COULD BE TICKED, not who is on the roster. A
	// clan of 239 here has 21 members with no checkbox at all -- you have
	// already sent to them, KoL has marked the account inactive, or it is you
	// -- so "191 of 239" names a total that cannot be reached however many
	// boxes you tick, and a count whose ceiling is unreachable is a count
	// nobody can read. The page does not have to pass the number either: the
	// locked rows carry no <input>, so counting the boxes IS counting who
	// could be sent to.
	function careTickedText(ticked, tickable) {
		if (tickable === 0) return '';
		return ticked + ' of ' + tickable + ' ticked';
	}

	// What pressing "Send" in the table header should set every box to.
	//
	// ANY BOX STILL OFF MEANS TURN THEM ALL ON, and only a column that is
	// already full clears. That is what makes a second press undo the first
	// without having to remember anything: from the page's own opening state
	// -- 190 of 218, the ones that would get a package -- the first press
	// fills the column and the second empties it.
	//
	// The alternative, flipping each box, is a different control: it would
	// turn the 190 off and the 28 on, which is not "select all" and is not
	// anything anybody wants from a header.
	// WHAT THE TICKED ROWS COST. Three multiplications, and they are here
	// rather than in the ASH for one reason: the number being multiplied is
	// how many boxes are ticked, which exists only in this browser.
	//
	// The sentence they go into is still written server-side; these fill the
	// holes in it. Pinned by a test because the summary is the page's one
	// claim about what pressing a send button would do, and it said 190 and
	// priced 190 while three rows were ticked.
	//
	// `boxes` is "up to": a gift box is only bought for a recipient a plain
	// kmail is refused for, and whether somebody is in Hardcore or Ronin is
	// not something this page can see.
	function careSendTotals(ticked, meatEach, boxEach) {
		var n = ticked > 0 ? ticked : 0;
		return {
			count: n,
			meat: n * (meatEach > 0 ? meatEach : 0),
			boxes: n * (boxEach > 0 ? boxEach : 0)
		};
	}

	// WHETHER THE SEND BUTTON LIGHTS, and what it says when it does not.
	// COwliCK's three conditions, 2026-11-21: "at least one recipient must be
	// selected / at least 1 item or 1 meat must be in the package / the
	// package has to have a description."
	//
	// Returning the REASON and not just a boolean is the point. A button that
	// is simply dead tells you nothing, and the three conditions live in
	// three different parts of a long page -- the ticks are at the bottom,
	// the package and the note are at the top -- so the one place you are
	// looking when you wonder why is the button itself.
	//
	// One reason at a time, in the order you would fix them: there is no
	// point being told to tick somebody while the package is empty.
	function careSendState(ticked, hasStuff, hasNote) {
		if (!hasStuff) return { on: false, why: 'Put an item or some Meat in the package first.' };
		if (!hasNote) return { on: false, why: 'The package needs a note.' };
		if (ticked < 1) return { on: false, why: 'Tick somebody to send to.' };
		return { on: true, why: '' };
	}

	// "Send 3 Packages", and the singular when it is one.
	function careSendLabel(ticked) {
		return 'Send ' + ticked + (ticked === 1 ? ' Package' : ' Packages');
	}

	// HOW MANY TIMES ONE BATCH IS TRIED before the send gives up on it.
	//
	// RETRYING A BATCH IS SAFE, which is the only reason this exists: the send
	// endpoint re-reads your Outbox at the top of every request and refuses
	// anybody already in it (ar_care_send.ash), so a batch that got two of its
	// three kmails out and then lost KoLmafia sends the third on the retry and
	// nothing twice. The mailbox is the record, not this loop.
	//
	// Three, because the failures worth riding out are the momentary ones -- a
	// request KoLmafia did not answer, an answer that arrived truncated -- and
	// a stale password hash or a package the server refuses outright will fail
	// all three in about five seconds and say so. COwliCK, 2026-11-21: sending
	// must not "stop before all intended packages are sent".
	var SEND_TRIES = 3;
	var SEND_RETRY_MS = 2000;

	// One batch's answer, counted. THREE OUTCOMES AND NOT TWO: a recipient the
	// server refused because they already have a package is not a failure and
	// must not be coloured as one -- which matters most on a retry, where the
	// people the first attempt did reach come back exactly like that.
	//
	// `names` is only the genuine refusals, since "already had one" said twice
	// over is a list nobody needs and the count already says it.
	function careSendTally(entries) {
		var t = { went: 0, had: 0, failed: 0, names: [] };
		for (var i = 0; i < (entries || []).length; i++) {
			var e = entries[i];
			if (e.sent) t.went++;
			else if (e.had) t.had++;
			else {
				t.failed++;
				t.names.push(e.name + ' (' + e.why + ')');
			}
		}
		return t;
	}

	// THE ONE SENTENCE THE SEND EVER SAYS, in all five of its states, because
	// the state it was in and what it told you had come apart: "Stopped after
	// 15 sent. Reload to see where it got to." was printed after batches that
	// had just gone perfectly, over the correct line, by an `always` handler
	// written as though it were a failure handler (see ar_ask.js). It then said
	// it again at 18 and at 27, because the send had not stopped at all.
	//
	// So every state composes from the same counts, and none of them asks you
	// to reload: `done` and `stopped` reload themselves, and `gaveup`
	// deliberately does not -- the explanation of what went wrong is the one
	// thing a reload would throw away.
	function careSendLine(t) {
		var head = 'Sent ' + t.went
			+ (t.had ? ', ' + t.had + ' already had one' : '')
			+ (t.failed ? ', ' + t.failed + ' refused' : '');
		var names = t.names && t.names.length ? ' — ' + t.names.join(', ') : '';

		if (t.phase === 'retry') {
			return { text: head + ', ' + t.left + ' to go. ' + t.why
				+ ' Trying that batch again (' + t.tries + ' of ' + SEND_TRIES + ').',
				kind: 'busy' };
		}
		if (t.phase === 'gaveup') {
			// WHAT TO DO NEXT, not where to look: pressing Send again re-asks
			// for the whole list and the server refuses the ones already in
			// the mailbox, so a second press costs nothing and finishes the
			// job. That is also why this one does not reload.
			return { text: head + '. ' + t.why + ' ' + t.left
				+ ' not sent — press Send again to finish them.' + names, kind: 'err' };
		}
		if (t.phase === 'stopped') {
			return { text: head + '. Stopped, ' + t.left + ' not sent.'
				+ names + ' Redrawing…', kind: t.failed ? 'err' : 'done' };
		}
		if (t.phase === 'done') {
			return { text: head + '.' + names + ' Redrawing…',
				kind: t.failed ? 'err' : 'done' };
		}
		return { text: head + ', ' + t.left + ' to go' + names, kind: 'busy' };
	}

	function careTickAllTarget(states) {
		for (var i = 0; i < states.length; i++) {
			if (!states[i]) return true;
		}
		return false;
	}

	if (typeof module !== 'undefined' && module.exports) {
		module.exports = {
			careScanNext: careScanNext,
			careEta: careEta,
			careProgressText: careProgressText,
			careTickedText: careTickedText,
			careTickAllTarget: careTickAllTarget,
			careSendTotals: careSendTotals,
			careSendState: careSendState,
			careSendLabel: careSendLabel,
			careSendTally: careSendTally,
			careSendLine: careSendLine,
			PROFILE_MS: PROFILE_MS,
			SEND_TRIES: SEND_TRIES
		};
		return;
	}

	/* ---- everything below is the page ---- */

	var SCAN = '/ar_care_scan.ash';
	var PREFS = '/ar_care_prefs.ash';

	var scanButton, stopButton, progress, said, configSaid, packageSaid, tickedLine;
	var sendButton, sendWhy, sendSaid, stopSendButton;
	var ask, saveInConfig, saveInPackage, askSend;
	var sending = false;
	var stoppedSending = false;
	var armed = 0;
	var sendSize = 3;
	var heldItems = [];
	var running = false;
	var stopped = false;
	var startedAt = 0;
	var fetchedSoFar = 0;

	function say(text, kind) {
		if (!said) return;
		said.textContent = text || '';
		said.className = 'care-said ' + (kind || '');
	}

	// THE CONFIG BOX HAS ITS OWN LINE, and that is why ar_ask.js is a factory
	// rather than a function: a refusal is reported by whichever `say` the
	// asker was built with, and "Not a place this knows." appearing beside the
	// look-up button -- half a page from the checkbox that caused it -- is the
	// kind of misplacement that reads as an unrelated failure.
	function configSay(text, kind) {
		if (!configSaid) return;
		configSaid.textContent = text || '';
		configSaid.className = 'care-said ' + (kind || '');
	}

	function packageSay(text, kind) {
		if (!packageSaid) return;
		packageSaid.textContent = text || '';
		packageSaid.className = 'care-said ' + (kind || '');
	}

	function show(text) {
		if (progress) progress.textContent = text || '';
	}

	// Disabled WHILE IT RUNS, which is the other half of what was asked for:
	// the old page gave no sign it was working, and a second press of a button
	// that is already fetching 216 profiles starts a second scan of the same
	// queue.
	function setRunning(on) {
		running = on;
		if (scanButton) scanButton.disabled = on;
		if (stopButton) stopButton.hidden = !on;
	}

	function finish(why, state) {
		setRunning(false);
		if (why === 'stalled') {
			// Deliberately NOT a reload: the page would redraw identically and
			// swallow the only sentence explaining why it stopped.
			show('');
			say('KoLmafia stopped sending profiles back, with ' + state.todo
				+ ' still to look up. Try again in a moment.', 'err');
			return;
		}
		// Finished or stopped: the page redraws itself, because every label and
		// count on it is written server-side. See the note at the top.
		show(why === 'stopped' ? 'stopping…' : 'done — redrawing…');
		window.location.reload();
	}

	function step(state) {
		var next = careScanNext({
			stopped: stopped,
			todo: state.todo,
			fetched: state.fetched
		});

		if (next !== 'go') {
			finish(next, state);
			return;
		}

		// TIMED FROM THE FIRST BATCH, not from the press. The roster walk and
		// the mailbox read happen first and cost five requests between them,
		// and charging those to the profiles made the early estimate climb --
		// 86 seconds, then 96, then 98 -- while the real rate was steady.
		if (startedAt === 0) startedAt = new Date().getTime();

		ask(SCAN, { step: 1 }, function (answer) {
			fetchedSoFar += answer.fetched || 0;
			var now = {
				total: answer.total,
				todo: answer.todo,
				done: answer.done,
				fetched: answer.fetched,
				batch: answer.batch,
				pause: answer.pause,
				fetchedSoFar: fetchedSoFar,
				elapsedMs: new Date().getTime() - startedAt
			};
			show(careProgressText(now));

			// The pause belongs HERE, between one batch's answer and the next
			// batch's request, rather than inside the endpoint: a sleep on the
			// server side would hold a KoLmafia relay thread open doing
			// nothing, and KoLmafia serializes its requests.
			var wait = Math.max(0, now.pause || 0);
			setTimeout(function () { step(now); }, wait);
		}, null);
	}

	// Ask SCAN one thing, then work through the batches from what it says.
	//
	// EVERY PATH STARTS HERE and every path's counts come from the endpoint,
	// including "continue", which asks ?state=1 purely to find out where it
	// stands. A first batch stepped from numbers this file made up would draw a
	// progress line out of them.
	//
	// The `always` handler is what puts the buttons back when the answer was a
	// refusal: ar_ask.js calls `then` only on success but `always` on every
	// path, so a roster that did not come back has to be the case that
	// re-enables, or the page sits disabled with an error and no way to retry.
	// It reads that from the `ok` it is handed rather than from a flag of its
	// own -- see ar_ask.js for what the flags cost.
	function kickOff(params, waiting) {
		show(waiting);
		ask(SCAN, params, function (answer) {
			show(careProgressText({
				total: answer.total,
				todo: answer.todo,
				done: answer.done,
				batch: answer.batch,
				pause: answer.pause,
				fetchedSoFar: 0,
				elapsedMs: 0
			}));
			step({
				total: answer.total,
				todo: answer.todo,
				done: answer.done,
				fetched: null,
				batch: answer.batch,
				pause: answer.pause
			});
		}, function (ok) {
			if (ok) return;
			show('');
			setRunning(false);
		});
	}

	function begin() {
		if (running) return;
		stopped = false;
		// Zero, not now: step() starts the clock at the first batch, so the
		// roster walk and the mailbox read are not charged to the profiles.
		startedAt = 0;
		fetchedSoFar = 0;
		say('');
		setRunning(true);

		var mode = scanButton.getAttribute('data-mode');

		// "Look up again" means again: without forgetting what is held, it
		// would re-walk the roster, find every login still inside the week,
		// fetch nothing, and look exactly like a button that does not work.
		if (mode === 'again') {
			// Said before the request rather than after its answer: pressing
			// "Look up again" and seeing an empty line until the clear comes
			// back is a small version of the complaint this change is about.
			show('starting again…');
			ask(SCAN, { clear: 1 }, function () {
				kickOff({ roster: 1 }, 'reading the clan roster…');
			}, function (ok) {
				if (ok) return;
				setRunning(false);
			});
			return;
		}

		// "Continue" already has a held roster and owes only profiles, so it
		// does not re-walk it.
		if (mode === 'continue') {
			kickOff({ state: 1 }, 'picking up where it stopped…');
			return;
		}
		kickOff({ roster: 1 }, 'reading the clan roster…');
	}

	/* ---- the Config box ---- */

	// Saves one setting and says so.
	//
	// RELOAD IS PER SETTING, not per save. "Active Means" and the places
	// re-decide every verdict in the table below -- who is quiet, what a
	// package can be packed from -- and those verdicts are written
	// server-side, so the honest way to show the new ones is to ask the server
	// again. The note changes nothing but its own readout, and reloading on it
	// would throw away the Send ticks for no reason at all.
	//
	// `landed` is what tells a refusal from a save: ar_ask.js calls `then`
	// only on success and `always` on every path, and a control left showing a
	// value the server refused is a control that looks saved.
	// A SAVER PER BOX, because a refusal has to appear under the control that
	// caused it. ar_ask.js reports through whichever `say` the asker was
	// built with, so "That is not an item." written beside the Config
	// checkboxes -- a box and a half up the page from the row being typed in
	// -- would read as an unrelated failure. This is what the factory in
	// ar_ask.js is for.
	function saverFor(say) {
		var asker = window.arAsk.make(window.arPwd, say);
		return function (name, value, opts) {
			opts = opts || {};
			say('Saving…', 'busy');
			asker(PREFS, { name: name, value: value }, function () {
				if (opts.saved) opts.saved();
				if (opts.reload) {
					say('Saved — redrawing…', 'done');
					window.location.reload();
					return;
				}
				say('Saved.', 'done');
			}, function (ok) {
				if (ok) return;
				// The refusal itself is already on the line, written by
				// ar_ask.js. All that is left is to put the control back to
				// what the server still holds.
				if (opts.revert) opts.revert();
			});
		};
	}

	function placesOn() {
		var on = [];
		var boxes = document.querySelectorAll('.care-place');
		for (var i = 0; i < boxes.length; i++) {
			if (boxes[i].checked) on.push(boxes[i].getAttribute('data-place'));
		}
		return on;
	}

	function bindConfig() {
		var days = document.getElementById('care-days');
		if (days) {
			var lastDays = days.value;
			days.onchange = function () {
				saveInConfig('arCareDays', days.value, {
					reload: true,
					revert: function () { days.value = lastDays; }
				});
			};
		}

		var boxes = document.querySelectorAll('.care-place');
		for (var i = 0; i < boxes.length; i++) {
			boxes[i].onchange = (function (box) {
				return function () {
					var on = placesOn();
					// STOPPED HERE RATHER THAN AT THE SERVER, the same way the
					// anti-raffle's sources are: the server would refuse this
					// too, but unticking the last box and being told off is a
					// worse answer than the box refusing to come off, and the
					// request is not worth making to find out.
					if (!on.length) {
						box.checked = true;
						configSay('Leave at least one place on.', 'err');
						return;
					}
					saveInConfig('arCareSources', on.join(','), {
						reload: true,
						revert: function () { box.checked = !box.checked; }
					});
				};
			})(boxes[i]);
		}
	}

	/* ---- the Package box ---- */

	// WHAT THE ROWS ADD UP TO, one entry per line.
	//
	// NEWLINES AND NOT COMMAS, which is the whole reason this is not just a
	// join(', '). The stored preference is comma-separated -- KoLmafia's own
	// item-list syntax -- and real giftable items have commas in their names:
	// "Oh, the Humanitini", "Ouija Board, Ouija Board". Sending those in a
	// comma list would arrive as entries that resolve to nothing, and the box
	// would refuse an item it had just suggested. ar_care_prefs.ash converts
	// to the stored form and knows how to write the awkward ones.
	//
	// A ROW WITH NO ITEM IS NOT AN ENTRY, which is also how a row is deleted:
	// clear the name and it stops being part of the package.
	function packageLines() {
		var lines = [];
		var rows = document.querySelectorAll('#care-rows .care-send-row');
		for (var i = 0; i < rows.length; i++) {
			var name = rows[i].querySelector('.care-item').value.trim();
			if (!name) continue;
			var qty = rows[i].querySelector('.care-qty').value.trim() || '1';
			lines.push(qty + ' ' + name);
		}
		return lines.join('\n');
	}

	function saveRows() {
		saveInPackage('arCarePackage', packageLines(), { reload: true });
	}

	function bindRow(row) {
		var qty = row.querySelector('.care-qty');
		var item = row.querySelector('.care-item');
		if (!qty || !item) return;

		// The box's list, drawn under it. A half-install leaves the row a
		// plain text field that still works -- you can type a name and it is
		// still checked -- which is the right way for a suggestion list to
		// be missing.
		if (window.arCombo) {
			window.arCombo.attach(item, function () { return heldItems; });
		}

		// A QUANTITY ALONE SAVES NOTHING. Typing 3 into an empty row and
		// tabbing out is halfway through naming an item, not a change to the
		// package -- saving there would reload the page out from under you
		// before you had said what three of.
		qty.onchange = function () {
			if (item.value.trim()) saveRows();
		};
		item.onchange = saveRows;
	}

	function bindPackage() {
		var rows = document.querySelectorAll('#care-rows .care-send-row');
		for (var i = 0; i < rows.length; i++) bindRow(rows[i]);

		var add = document.getElementById('care-add-row');
		if (add) {
			add.onclick = function (event) {
				// A link, the way KoL's + is, so it needs the href stopped.
				event.preventDefault();
				var all = document.querySelectorAll('#care-rows .care-send-row');
				if (!all.length) return;
				// CLONED FROM THE LAST ROW rather than built here, so there is
				// one description of what a row is and it lives in the ASH
				// that writes the page. A second one here would be the thing
				// that drifted.
				var fresh = all[all.length - 1].cloneNode(true);
				fresh.querySelector('.care-qty').value = '1';
				fresh.querySelector('.care-item').value = '';
				// The clone carries a copy of the last row's suggestion list,
				// markup and all. arCombo.attach throws its own away and
				// builds a fresh one, but the clone must not be inserted
				// holding two.
				var stale = fresh.querySelector('.ar-combo-list');
				if (stale) stale.parentNode.removeChild(stale);
				// The + lives in the first row, so cloning that row -- which
				// is what happens when it is the only one -- would carry a
				// second + down the stack, each with the same id.
				var plus = fresh.querySelector('.care-plus');
				if (plus) plus.parentNode.removeChild(plus);
				document.getElementById('care-rows').appendChild(fresh);
				bindRow(fresh);
				fresh.querySelector('.care-item').focus();
			};
		}

		var meat = document.getElementById('care-meat');
		if (meat) {
			var lastMeat = meat.value;
			meat.onchange = function () {
				saveInPackage('arCareMeat', meat.value, {
					reload: true,
					revert: function () { meat.value = lastMeat; }
				});
			};
		}

		var note = document.getElementById('care-note-text');
		if (note) {
			// THE LAST VALUE THE SERVER ACCEPTED, moved on only when it has
			// accepted another. Updating it at the moment of asking is the
			// easy mistake: a note refused for being too long would then be
			// "reverted" to itself, and the box would keep a value the
			// preference does not have.
			var lastNote = note.value;
			note.onchange = function () {
				var asked = note.value;
				var before = lastNote;
				saveInPackage('arCareNote', asked, {
					saved: function () { lastNote = asked; },
					revert: function () { note.value = before; }
				});
			};
		}
	}

	// The suggestions, fetched once, after the page has drawn.
	//
	// NOT WRITTEN INTO THE PAGE. On this character the list is about two
	// thousand items; served as markup that is a third of the page's weight,
	// paid on every load, for something nothing needs until a box is focused.
	//
	// Held in one array that every row's box reads through a closure, so the
	// rows share the one copy and a row added later gets the list without
	// asking for it again.
	function loadItems() {
		if (!document.getElementById('care-rows')) return;
		ask('/ar_care_items.ash', { have: 1 }, function (answer) {
			heldItems = (answer.held || []).sort(function (a, b) {
				return a.name.toLowerCase().localeCompare(b.name.toLowerCase());
			});
		}, null);
	}

	/* ---- sending ---- */

	// ARMED FOR THIS LONG after the first press, then it goes back to being
	// an ordinary button. Long enough to mean the second press, short enough
	// that a button left armed while you wander off does not stay a single
	// tap away from mailing the clan.
	var ARM_MS = 8000;

	function tickedWho() {
		var who = [];
		var boxes = document.querySelectorAll('.care-tick');
		for (var i = 0; i < boxes.length; i++) {
			if (boxes[i].checked) who.push(boxes[i].getAttribute('data-who'));
		}
		return who;
	}

	// Everything on the page that must not move while a send is running. A
	// package edited halfway through would send two different packages, and
	// a tick changed would not be in the list the send is working through.
	function freeze(on) {
		var controls = document.querySelectorAll('#care-days, #care-note-text,'
			+ ' #care-meat, #care-add-row, .care-place, .care-qty, .care-item,'
			+ ' .care-tick, #care-scan, #care-tick-all');
		for (var i = 0; i < controls.length; i++) {
			if (controls[i].tagName === 'A') {
				controls[i].style.pointerEvents = on ? 'none' : '';
				controls[i].style.opacity = on ? '0.5' : '';
			} else {
				controls[i].disabled = on;
			}
		}
	}

	function paintSendButton() {
		if (!sendButton) return;
		if (sending) return;
		var state = careSendState(tickedWho().length,
			sendButton.getAttribute('data-stuff') === '1',
			sendButton.getAttribute('data-note') === '1');
		sendButton.disabled = !state.on;
		sendButton.textContent = careSendLabel(tickedWho().length);
		if (sendWhy) sendWhy.textContent = state.why;
		// Any change to the page disarms it: the number on the button is the
		// number you agreed to, so if it moves the agreement is stale.
		disarm();
	}

	function disarm() {
		if (armed) {
			window.clearTimeout(armed);
			armed = 0;
		}
		if (sendButton && !sending) sendButton.classList.remove('care-armed');
	}

	function sendSay(text, kind) {
		if (!sendSaid) return;
		sendSaid.textContent = text || '';
		sendSaid.className = 'care-said ' + (kind || '');
	}

	// One batch, then the next, with the queue held here. The server decides
	// how many a batch is and reports what happened to each name.
	//
	// `run` is what the whole send has done so far -- went, had, failed and
	// the refusal names -- rather than three loose counters, because the line
	// and the ending both report all of it and careSendLine() takes it whole.
	// `tries` counts attempts at the batch currently in hand and resets with
	// each new one.
	function sendBatch(queue, run, tries) {
		if (stoppedSending || !queue.length) {
			finishSend(queue, run, stoppedSending && queue.length ? 'stopped' : 'done', '');
			// A reload, so the table comes back with the people who have now
			// had one moved into "already had one" -- read out of the mailbox
			// rather than assumed from what this loop thinks it did.
			window.location.reload();
			return;
		}

		var take = queue.slice(0, sendSize);
		askSend('/ar_care_send.ash', { to: take.join(',') }, function (answer) {
			var got = answer.done || [];
			if (answer.batch > 0) sendSize = answer.batch;
			var batch = careSendTally(got);
			run.went += batch.went;
			run.had += batch.had;
			run.failed += batch.failed;
			run.names = run.names.concat(batch.names);
			// THE SERVER SAYS WHO IT DEALT WITH, and the queue drops exactly
			// those. Dropping `take` instead would skip anybody the server
			// did not get to -- it stops at its own batch size, not ours.
			queue = queue.slice(got.length || take.length);
			tell(run, queue.length, '', 0);
			if (sendButton) sendButton.textContent = 'Sending… ' + queue.length + ' to go';
			window.setTimeout(function () { sendBatch(queue, run, 1); }, 400);
		}, function (ok, why) {
			// ONLY THE PATHS THAT DID NOT REACH THE ANSWER, which is what the
			// `ok` is for: this handler runs after a successful batch too, and
			// written as though it were a failure handler it printed "Stopped
			// after 15 sent" over the line a batch had just earned -- without
			// stopping anything, since the batch above had already queued the
			// next one. See ar_ask.js.
			if (ok) return;

			// THE SAME BATCH AGAIN, not the next one and not the end of the
			// send. A momentary failure is the common one and the endpoint is
			// safe to re-ask (SEND_TRIES, above), so the queue does not move
			// and nobody is skipped.
			if (tries < SEND_TRIES) {
				tell(run, queue.length, why, tries + 1);
				window.setTimeout(function () {
					sendBatch(queue, run, tries + 1);
				}, SEND_RETRY_MS);
				return;
			}

			// Out of tries. NO RELOAD HERE, unlike every other ending: the
			// sentence explaining what went wrong is the one thing worth
			// keeping on screen, and a second press of Send picks up the rest.
			finishSend(queue, run, 'gaveup', why);
			if (sendButton) paintSendButton();
		});
	}

	// The progress line, mid-send. `tries` of 0 means this is an ordinary
	// batch rather than a retry.
	function tell(run, left, why, tries) {
		var said = careSendLine({
			went: run.went, had: run.had, failed: run.failed, names: run.names,
			left: left, why: why, tries: tries,
			phase: tries > 0 ? 'retry' : 'busy'
		});
		sendSay(said.text, said.kind);
	}

	function finishSend(queue, run, phase, why) {
		freeze(false);
		sending = false;
		var said = careSendLine({
			went: run.went, had: run.had, failed: run.failed, names: run.names,
			left: queue.length, why: why, phase: phase
		});
		sendSay(said.text, said.kind);
	}

	function beginSend() {
		var queue = tickedWho();
		if (!queue.length) return;
		sending = true;
		stoppedSending = false;
		disarm();
		freeze(true);
		sendButton.disabled = true;
		sendButton.textContent = 'Sending… ' + queue.length + ' to go';
		if (stopSendButton) stopSendButton.hidden = false;
		sendSay('Sending…', 'busy');
		sendBatch(queue, { went: 0, had: 0, failed: 0, names: [] }, 1);
	}

	function bindSend() {
		sendButton = document.getElementById('care-send');
		sendWhy = document.getElementById('care-send-why');
		sendSaid = document.getElementById('care-send-said');
		stopSendButton = document.getElementById('care-send-stop');
		if (!sendButton) return;

		// A RAW ASKER, not saverFor(). saverFor returns a saver whose
		// signature is (name, value, opts) and which always posts to
		// ar_care_prefs.ash -- so built that way, the send posted
		// `name=/ar_care_send.ash` to the settings endpoint, was correctly
		// told "Not a setting this touches", and never called back at all,
		// which left the page frozen mid-send with nothing sent. Caught on
		// the first real send; nothing left the machine.
		askSend = window.arAsk.make(window.arPwd, sendSay);

		// TWO PRESSES. The first arms and says what the second will do; the
		// second sends. COwliCK's call when asked, and the reason is that
		// this mails a couple of hundred people irreversibly from a button
		// sitting directly under the editor for what it mails them.
		//
		// Done in the page rather than with confirm(), which in a WKWebView
		// whose host implements no dialog delegate returns false at once and
		// draws nothing -- the button would never fire at all on the iPad
		// this is read on.
		sendButton.addEventListener('click', function () {
			if (sending) return;
			var n = tickedWho().length;
			if (armed) {
				beginSend();
				return;
			}
			sendButton.classList.add('care-armed');
			sendButton.textContent = 'Really send ' + n
				+ (n === 1 ? ' package?' : ' packages?');
			sendSay('Press again to send. There is no unsend.', 'err');
			armed = window.setTimeout(function () {
				armed = 0;
				sendButton.classList.remove('care-armed');
				sendSay('');
				paintSendButton();
			}, ARM_MS);
		});

		if (stopSendButton) {
			stopSendButton.addEventListener('click', function () {
				stoppedSending = true;
				sendSay('Stopping after this batch…', 'busy');
			});
		}

		paintSendButton();
	}

	/* ---- the Send ticks ---- */

	// Counted off the document, never worked out again here. Which rows may be
	// ticked is decided in ASH (careTickable, ar_care.ash) and arrives as the
	// presence of an <input>; this only ever counts what is there.
	function fill(selector, value) {
		var holes = document.querySelectorAll(selector);
		for (var i = 0; i < holes.length; i++) holes[i].textContent = value;
	}

	function countTicks() {
		var boxes = document.querySelectorAll('.care-tick');
		var ticked = 0;
		for (var i = 0; i < boxes.length; i++) {
			if (boxes[i].checked) ticked++;
		}
		if (tickedLine) tickedLine.textContent = careTickedText(ticked, boxes.length);
		// The button's label is the number of recipients and its enabled-ness
		// is partly that number, so it moves with every tick.
		paintSendButton();

		// THE SUMMARY COUNTS THE SAME TICKS. It is the page's one claim about
		// what a send would do, and before this it counted who was eligible
		// instead -- so unticking everybody but three left it saying 190 and
		// pricing 190 packages.
		var summary = document.getElementById('care-summary');
		if (!summary) return;
		var totals = careSendTotals(ticked,
			parseInt(summary.getAttribute('data-meat'), 10) || 0,
			parseInt(summary.getAttribute('data-box'), 10) || 0);
		fill('#care-summary .care-n', totals.count);
		fill('#care-summary .care-meat-all', totals.meat);
		fill('#care-summary .care-box-all', totals.boxes);
	}

	// ONE LISTENER ON THE TABLE, not 218 on the boxes. A clan of a couple of
	// hundred is a couple of hundred rows, and a change event from any of them
	// bubbles to here.
	function bindTicks() {
		var table = document.querySelector('.care-list');
		if (table) {
			table.addEventListener('change', function (event) {
				var hit = event.target;
				if (hit && hit.classList && hit.classList.contains('care-tick')) countTicks();
			});
		}

		// WHAT THEY HAVE HAD, unfolded under their row. The detail is already
		// in the page, hidden, so this only flips `hidden` -- there is
		// nothing to fetch and nothing to compose, which is why it opens
		// instantly and why there is no spinner to get wrong.
		//
		// ONE LISTENER ON THE TABLE, like the ticks: a clan is a couple of
		// hundred rows and a listener each is a couple of hundred listeners
		// for something pressed once in a while.
		if (table) {
			table.addEventListener('click', function (event) {
				var hit = event.target;
				if (!hit || !hit.classList
					|| !hit.classList.contains('care-gift-open')) return;
				event.preventDefault();
				var row = hit.closest('tr');
				var detail = row && row.nextElementSibling;
				if (!detail || !detail.classList.contains('care-gift-row')) return;
				detail.hidden = !detail.hidden;
				hit.classList.toggle('care-gift-shown', !detail.hidden);
			});
		}

		var all = document.getElementById('care-tick-all');
		if (all) {
			all.onclick = function (event) {
				event.preventDefault();
				var boxes = document.querySelectorAll('.care-tick');
				var states = [];
				for (var i = 0; i < boxes.length; i++) states.push(boxes[i].checked);
				var want = careTickAllTarget(states);
				for (var j = 0; j < boxes.length; j++) boxes[j].checked = want;
				// Setting .checked from script fires no change event, so the
				// listener above never runs and the count would sit at
				// whatever it said before.
				countTicks();
			};
		}

		countTicks();
	}

	function start() {
		scanButton = document.getElementById('care-scan');
		stopButton = document.getElementById('care-stop');
		progress = document.getElementById('care-progress');
		said = document.getElementById('care-said');
		configSaid = document.getElementById('care-config-said');
		packageSaid = document.getElementById('care-package-said');
		tickedLine = document.getElementById('care-ticked');

		// A HALF-INSTALL SAYS SO. These two files ship together and the page
		// emits both tags in order, but copying one of them into the relay
		// folder by hand is how a change gets tried out -- and without this
		// the controls would all be there, press cleanly, and do nothing at
		// all. Said in both places, because by now there are controls in both
		// boxes and either one is where you might be looking.
		if (!window.arAsk) {
			if (scanButton) scanButton.disabled = true;
			var dead = document.querySelectorAll('#care-days, #care-note-text,'
				+ ' #care-meat, #care-add-row, .care-place, .care-qty, .care-item,'
				+ ' #care-send');
			for (var i = 0; i < dead.length; i++) dead[i].disabled = true;
			var missing = 'ar_ask.js did not load, so nothing here can be saved'
				+ ' or looked up. Reinstall the script, or reload.';
			say(missing, 'err');
			configSay(missing, 'err');
			packageSay(missing, 'err');
			return;
		}
		ask = window.arAsk.make(window.arPwd, say);
		saveInConfig = saverFor(configSay);
		saveInPackage = saverFor(packageSay);

		// BEFORE THE EARLY RETURN BELOW. The two setting boxes and the ticks
		// are there whether or not anything has been looked up yet, and a
		// page with no scan button -- which is not a state this page has, but
		// is one an edit could make -- should still save its settings.
		bindConfig();
		bindPackage();
		bindTicks();
		bindSend();
		loadItems();

		if (!scanButton) return;

		scanButton.addEventListener('click', begin);
		if (stopButton) {
			stopButton.addEventListener('click', function () {
				stopped = true;
				show('stopping after this batch…');
			});
		}
	}

	if (document.readyState === 'loading') {
		document.addEventListener('DOMContentLoaded', start);
	} else {
		start();
	}
})();
