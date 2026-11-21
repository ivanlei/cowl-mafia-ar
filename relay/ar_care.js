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

	if (typeof module !== 'undefined' && module.exports) {
		module.exports = {
			careScanNext: careScanNext,
			careEta: careEta,
			careProgressText: careProgressText,
			careTickedText: careTickedText,
			PROFILE_MS: PROFILE_MS
		};
		return;
	}

	/* ---- everything below is the page ---- */

	var SCAN = '/ar_care_scan.ash';
	var PREFS = '/ar_care_prefs.ash';

	var scanButton, stopButton, progress, said, configSaid, tickedLine;
	var ask, askConfig;
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
	function saveSetting(name, value, opts) {
		opts = opts || {};
		var landed = false;
		configSay('Saving…', 'busy');
		askConfig(PREFS, { name: name, value: value }, function () {
			landed = true;
			if (opts.saved) opts.saved();
			if (opts.reload) {
				configSay('Saved — redrawing…', 'done');
				window.location.reload();
				return;
			}
			configSay('Saved.', 'done');
		}, function () {
			if (landed) return;
			// The refusal itself is already on the line, written by ar_ask.js
			// through configSay. All that is left is to put the control back
			// to what the server still holds.
			if (opts.revert) opts.revert();
		});
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
				saveSetting('arCareDays', days.value, {
					reload: true,
					revert: function () { days.value = lastDays; }
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
				saveSetting('arCareNote', asked, {
					saved: function () { lastNote = asked; },
					revert: function () { note.value = before; }
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
					saveSetting('arCareSources', on.join(','), {
						reload: true,
						revert: function () { box.checked = !box.checked; }
					});
				};
			})(boxes[i]);
		}
	}

	/* ---- the Send ticks ---- */

	// Counted off the document, never worked out again here. Which rows may be
	// ticked is decided in ASH (careTickable, ar_care.ash) and arrives as the
	// presence of an <input>; this only ever counts what is there.
	function countTicks() {
		if (!tickedLine) return;
		var boxes = document.querySelectorAll('.care-tick');
		var ticked = 0;
		for (var i = 0; i < boxes.length; i++) {
			if (boxes[i].checked) ticked++;
		}
		tickedLine.textContent = careTickedText(ticked, boxes.length);
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
		countTicks();
	}

	function start() {
		scanButton = document.getElementById('care-scan');
		stopButton = document.getElementById('care-stop');
		progress = document.getElementById('care-progress');
		said = document.getElementById('care-said');
		configSaid = document.getElementById('care-config-said');
		tickedLine = document.getElementById('care-ticked');

		// A HALF-INSTALL SAYS SO. These two files ship together and the page
		// emits both tags in order, but copying one of them into the relay
		// folder by hand is how a change gets tried out -- and without this
		// the controls would all be there, press cleanly, and do nothing at
		// all. Said in both places, because by now there are controls in both
		// boxes and either one is where you might be looking.
		if (!window.arAsk) {
			if (scanButton) scanButton.disabled = true;
			var dead = document.querySelectorAll('#care-days, #care-note-text, .care-place');
			for (var i = 0; i < dead.length; i++) dead[i].disabled = true;
			var missing = 'ar_ask.js did not load, so nothing here can be saved'
				+ ' or looked up. Reinstall the script, or reload.';
			say(missing, 'err');
			configSay(missing, 'err');
			return;
		}
		ask = window.arAsk.make(window.arPwd, say);
		askConfig = window.arAsk.make(window.arPwd, configSay);

		// BEFORE THE EARLY RETURN BELOW. The Config box and the ticks are
		// there whether or not anything has been looked up yet, and a page
		// with no scan button -- which is not a state this page has, but is
		// one an edit could make -- should still save its settings.
		bindConfig();
		bindTicks();

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
