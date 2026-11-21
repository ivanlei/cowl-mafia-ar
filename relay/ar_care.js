// ar_care.js -- the Care Packages page's look-up button.
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

	if (typeof module !== 'undefined' && module.exports) {
		module.exports = {
			careScanNext: careScanNext,
			careEta: careEta,
			careProgressText: careProgressText,
			PROFILE_MS: PROFILE_MS
		};
		return;
	}

	/* ---- everything below is the page ---- */

	var SCAN = '/ar_care_scan.ash';

	var scanButton, stopButton, progress, note;
	var ask;
	var running = false;
	var stopped = false;
	var startedAt = 0;
	var fetchedSoFar = 0;

	function say(text, kind) {
		if (!note) return;
		note.textContent = text || '';
		note.className = kind || '';
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
	// `advanced` is what puts the buttons back when the answer was a refusal:
	// ar_ask.js calls `then` only on success but `always` on every path, so a
	// roster that did not come back has to be the case that re-enables, or the
	// page sits disabled with an error and no way to retry.
	function kickOff(params, waiting) {
		var advanced = false;
		show(waiting);
		ask(SCAN, params, function (answer) {
			advanced = true;
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
		}, function () {
			if (advanced) return;
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
			var cleared = false;
			// Said before the request rather than after its answer: pressing
			// "Look up again" and seeing an empty line until the clear comes
			// back is a small version of the complaint this change is about.
			show('starting again…');
			ask(SCAN, { clear: 1 }, function () {
				cleared = true;
				kickOff({ roster: 1 }, 'reading the clan roster…');
			}, function () {
				if (cleared) return;
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

	function start() {
		scanButton = document.getElementById('care-scan');
		stopButton = document.getElementById('care-stop');
		progress = document.getElementById('care-progress');
		note = document.getElementById('care-note');
		if (!scanButton) return;

		// A HALF-INSTALL SAYS SO. These two files ship together and the page
		// emits both tags in order, but copying one of them into the relay
		// folder by hand is how a change gets tried out -- and without this
		// the button would be there, press cleanly, and do nothing at all.
		if (!window.arAsk) {
			scanButton.disabled = true;
			say('ar_ask.js did not load, so the look-up cannot run.'
				+ ' Reinstall the script, or reload.', 'err');
			return;
		}
		ask = window.arAsk.make(window.arPwd, say);

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
