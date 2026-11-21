// tests/ar_care_tick.test.js -- the Send column's count.
//
// WHY THIS IS WORTH A TEST AT ALL. It is one sentence, but it is the only
// number on the Care Packages page that the server does not write, and it is
// the number you would read before pressing a send button that does not exist
// yet. Its one real decision is the DENOMINATOR, and that decision is easy to
// get wrong in a way nobody notices:
//
// The clan has 239 members and 218 checkboxes. The missing 21 are people you
// have already sent to, accounts KoL has marked inactive, and you -- none of
// whom gets a box at all (careTickable, in ar_care.ash). So "191 of 239" names
// a ceiling that cannot be reached however many boxes are ticked, and a count
// you can never complete is a count nobody trusts. The page does not pass the
// total in either: the locked rows carry no <input>, so counting the boxes IS
// counting who could be sent to, and the two can never disagree.
//
// Run by .github/check.py with a plain `node <file>`, like every other test
// here, so there is nothing asynchronous in it.

var assert = require('assert');
var care = require('../relay/ar_care.js');

var failures = 0;

function ok(what, got, want) {
	try {
		assert.deepStrictEqual(got, want);
		console.log('ok   ' + what);
	} catch (e) {
		failures++;
		console.log('FAIL ' + what + ': got ' + JSON.stringify(got)
			+ ', wanted ' + JSON.stringify(want));
	}
}

/* ---- careTickedText ---- */

// The real shape of COwliCK's clan on the day this was written: 239 members,
// 218 of them with a box, 191 of those ticked by default.
ok('counts the ticks against the boxes, not against the roster',
	care.careTickedText(191, 218), '191 of 218 ticked');

ok('none ticked still names the ceiling',
	care.careTickedText(0, 218), '0 of 218 ticked');

ok('all of them',
	care.careTickedText(218, 218), '218 of 218 ticked');

ok('one is not special',
	care.careTickedText(1, 218), '1 of 218 ticked');

// NO BOXES IS NO SENTENCE, not "0 of 0 ticked". The page draws this span
// whenever it has rows, and a clan where everyone has already had one -- or
// a page with nothing looked up yet -- would otherwise carry a line of
// arithmetic about nobody.
ok('says nothing at all when there is nobody to tick',
	care.careTickedText(0, 0), '');

/* ---- careTickAllTarget: what pressing "Send" sets every box to ---- */

// THE OPENING STATE OF THE PAGE is a column that is mostly but not entirely
// ticked -- the ones that would get a package are on, the quiet and skipped
// ones are off -- so this is the press that matters and it has to fill the
// column, not empty it.
ok('fills the column when some are off',
	care.careTickAllTarget([true, true, false, true]), true);

// And only then does a press clear it, which is what makes the second press
// undo the first with nothing remembered in between.
ok('clears it only when every one is on',
	care.careTickAllTarget([true, true, true]), false);

ok('fills it when none are on',
	care.careTickAllTarget([false, false]), true);

ok('one box off is enough',
	care.careTickAllTarget([true, true, true, true, false]), true);

// A table with no boxes at all: every row locked, or nothing looked up yet.
// Nothing to fill, so "clear" is the harmless answer -- and the press has
// nothing to act on either way.
ok('an empty column clears', care.careTickAllTarget([]), false);

/* ---- careSendTotals: what the summary says a send would cost ---- */

// THE BUG THIS IS FOR. The summary was written server-side from the number
// of ELIGIBLE members, and the Send column then made the number of
// RECIPIENTS a thing only the browser knows. Unticking everybody but three
// left the page saying "190 of 239 clan members would get a package — 47500
// Meat in all, plus 190× (…)" with three rows ticked. COwliCK found it.
ok('prices what is ticked, not what is eligible',
	care.careSendTotals(3, 250, 1000), { count: 3, meat: 750, boxes: 3000 });

ok('and the full column',
	care.careSendTotals(218, 250, 1000), { count: 218, meat: 54500, boxes: 218000 });

// No Meat in the package is the common case, and zero times anything has to
// stay zero rather than become the gift-box number by accident.
ok('no Meat set costs no Meat',
	care.careSendTotals(190, 0, 1000), { count: 190, meat: 0, boxes: 190000 });

ok('nothing ticked costs nothing',
	care.careSendTotals(0, 250, 1000), { count: 0, meat: 0, boxes: 0 });

// A missing data attribute parses to NaN and is passed in as 0 by the
// caller; a negative one should not credit you Meat either.
ok('a nonsense unit cost is treated as none',
	care.careSendTotals(5, -250, 1000), { count: 5, meat: 0, boxes: 5000 });

ok('and a nonsense count is treated as none',
	care.careSendTotals(-4, 250, 1000), { count: 0, meat: 0, boxes: 0 });

/* ---- careSendState: whether the send button lights, and why not ---- */

// COwliCK's three conditions, 2026-11-21: "at least one recipient must be
// selected / at least 1 item or 1 meat must be in the package / the package
// has to have a description."
ok('all three met', care.careSendState(190, true, true), { on: true, why: '' });
ok('one recipient is enough', care.careSendState(1, true, true), { on: true, why: '' });

// THE REASON IS THE POINT, not the boolean. The three conditions live at
// opposite ends of a long page -- the ticks at the bottom, the package and
// the note at the top -- so a button that is merely dead tells you nothing
// about which of them to go and fix.
ok('nobody ticked', care.careSendState(0, true, true).on, false);
ok('and it says so', care.careSendState(0, true, true).why, 'Tick somebody to send to.');

ok('an empty package', care.careSendState(190, false, true).on, false);
ok('and it says so', care.careSendState(190, false, true).why,
	'Put an item or some Meat in the package first.');

ok('no note', care.careSendState(190, true, false).on, false);
ok('and it says so', care.careSendState(190, true, false).why, 'The package needs a note.');

// ONE REASON AT A TIME, in the order you would fix them: being told to tick
// somebody while the package is still empty is advice about the wrong end.
ok('the package comes before the ticks',
	care.careSendState(0, false, true).why, 'Put an item or some Meat in the package first.');
ok('and before the note',
	care.careSendState(0, false, false).why, 'Put an item or some Meat in the package first.');
ok('the note comes before the ticks',
	care.careSendState(0, true, false).why, 'The package needs a note.');

/* ---- careSendLabel ---- */

ok('the button counts the recipients', care.careSendLabel(190), 'Send 190 Packages');
ok('one is singular', care.careSendLabel(1), 'Send 1 Package');
// Shown while the button is disabled, so it still has to read as English.
ok('none is plural', care.careSendLabel(0), 'Send 0 Packages');

/* ---- careSendTally: one batch's answer, counted ---- */

// THREE OUTCOMES AND NOT TWO. "already had one" is a refusal in the sense that
// nothing was sent, and not a failure in any sense that should be coloured red
// -- and the retry below makes that the difference between a line that reads
// as a hiccup and one that reads as a disaster.
ok('a clean batch',
	care.careSendTally([{ sent: true }, { sent: true }, { sent: true }]),
	{ went: 3, had: 0, failed: 0, names: [] });

ok('the three outcomes apart',
	care.careSendTally([
		{ sent: true, name: 'A' },
		{ sent: false, had: true, name: 'B', why: 'already had one' },
		{ sent: false, had: false, name: 'C', why: 'KoL did not take it' }
	]),
	{ went: 1, had: 1, failed: 1, names: ['C (KoL did not take it)'] });

// THE RETRY'S OWN SHAPE: a batch that got two kmails out and then lost
// KoLmafia comes back, on the second attempt, as two who already have one and
// one that went. Nothing failed, and the line must not say anything did.
ok('a retried batch is not a failed one',
	care.careSendTally([
		{ sent: false, had: true, name: 'A', why: 'already had one' },
		{ sent: false, had: true, name: 'B', why: 'already had one' },
		{ sent: true, name: 'C' }
	]),
	{ went: 1, had: 2, failed: 0, names: [] });

ok('nothing at all', care.careSendTally([]), { went: 0, had: 0, failed: 0, names: [] });
ok('and a missing list', care.careSendTally(undefined),
	{ went: 0, had: 0, failed: 0, names: [] });

/* ---- careSendLine: what the send says, in each of its five states ---- */

function run(extra) {
	var t = { went: 0, had: 0, failed: 0, names: [], left: 0, why: '', tries: 0 };
	for (var k in extra) if (extra.hasOwnProperty(k)) t[k] = extra[k];
	return t;
}

ok('mid-send',
	care.careSendLine(run({ went: 3, left: 187 })).text,
	'Sent 3, 187 to go');

ok('mid-send with somebody who already had one',
	care.careSendLine(run({ went: 3, had: 1, left: 186 })).text,
	'Sent 3, 1 already had one, 186 to go');

ok('mid-send with a refusal named',
	care.careSendLine(run({ went: 3, failed: 1, names: ['A (KoL did not take it)'], left: 186 })).text,
	'Sent 3, 1 refused, 186 to go — A (KoL did not take it)');

// A batch that already had one is not an error state, so the line stays busy.
ok('already-had-one does not colour the line',
	care.careSendLine(run({ went: 3, had: 2, left: 100 })).kind, 'busy');
ok('a real refusal does',
	care.careSendLine(run({ went: 3, failed: 1, names: ['A (x)'], left: 100, phase: 'done' })).kind, 'err');

// THE RETRY, which is the whole of COwliCK's second complaint: "sending stops
// before all intended packages are sent" is not the expected result, so a
// momentary failure says what happened, says how long it is waiting, and goes
// round again.
ok('a retry says who, how long and which attempt',
	care.careSendLine(run({ went: 69, left: 61, why: 'KoLmafia did not answer (404).',
		tries: 2, waitMs: 10000, one: 'Someclanmate', phase: 'retry' })).text,
	'Sent 69, 61 to go. KoLmafia did not answer (404). Trying Someclanmate on their own in 10s (2 of 4).');

// Without a name to put to it -- a row that has scrolled out of the table,
// say -- it still has to read as English.
ok('and without a name',
	care.careSendLine(run({ went: 69, left: 61, why: 'Boom.', tries: 3,
		waitMs: 30000, phase: 'retry' })).text,
	'Sent 69, 61 to go. Boom. Trying again in 30s (3 of 4).');

ok('and a retry is not an error, it is progress',
	care.careSendLine(run({ went: 15, left: 175, why: 'x', tries: 2, waitMs: 2000,
		phase: 'retry' })).kind,
	'busy');

// GIVING UP, which is the only ending that leaves anybody unsent, and says
// what to do about it rather than where to look.
ok('giving up names what is left and how to finish it',
	care.careSendLine(run({ went: 15, left: 175, why: 'KoLmafia did not answer (0).',
		phase: 'gaveup' })).text,
	'Sent 15. KoLmafia did not answer (0). 175 not sent — press Send again to finish them.');

ok('the two endings that redraw themselves say so',
	care.careSendLine(run({ went: 190, phase: 'done' })).text,
	'Sent 190. Redrawing…');
ok('and the Stop button',
	care.careSendLine(run({ went: 15, left: 175, phase: 'stopped' })).text,
	'Sent 15. Stopped, 175 not sent. Redrawing…');

// THE NAMES BELONG TO THE COUNT, not to the sentence after it. Written the
// other way round the end of a run with somebody set aside read "Sent 0, 5
// already had one, 1 refused. - Someclanmate (KoL would not take it) Redrawing...",
// with a full stop in the middle of its own clause.
ok('an ending names who was set aside, before its full stop',
	care.careSendLine(run({ went: 0, had: 5, failed: 1,
		names: ['Someclanmate (KoL would not take it)'], phase: 'done' })).text,
	'Sent 0, 5 already had one, 1 refused — Someclanmate (KoL would not take it). Redrawing…');
ok('and so does a stop',
	care.careSendLine(run({ went: 3, failed: 1, names: ['A (x)'], left: 9,
		phase: 'stopped' })).text,
	'Sent 3, 1 refused — A (x). Stopped, 9 not sent. Redrawing…');

// THE REGRESSION, pinned by name. The old line was "Stopped after 15 sent.
// Reload to see where it got to." -- printed by an `always` handler written as
// though it were a failure handler, after batches that had gone perfectly, and
// printed again at 18 and at 27 because nothing had stopped. Two things were
// wrong with the sentence itself even when the stop was real: the send already
// reloads itself at every ending that has anything to redraw, and the loop
// knows exactly who went, so "see where it got to" was advice to go and find
// out something it had just been told.
var everyState = ['busy', 'retry', 'done', 'stopped', 'gaveup'];
everyState.forEach(function (phase) {
	var text = care.careSendLine(run({ went: 15, had: 1, failed: 1, names: ['A (x)'],
		left: 175, why: 'something.', tries: 2, waitMs: 2000, phase: phase })).text;
	ok('nothing in the ' + phase + ' line asks for a reload',
		/reload/i.test(text), false);
	ok('and nothing in the ' + phase + ' line claims it stopped after a count',
		/stopped after/i.test(text), false);
});

/* ---- careSendAfterFailure: what a 404 costs ---- */

// THE BUG THIS IS THE FIX FOR, and it is worth stating exactly because the
// shape of it is not obvious. A send KoLmafia will not complete sets an error
// state; an error state aborts the ASH relay script; ar_care_send.ash writes
// its whole answer at the end, so nothing has been written; and KoLmafia
// serves a script that wrote nothing as HTTP 404. So ONE recipient KoL will
// not take produces a 404 that says nothing about who, and the first version
// of the retry answered it by asking for the same three people three times
// and then stopping -- "Sent 69. KoLmafia did not answer (404). 61 not sent."
//
// A FAILURE IS NARROWED BEFORE IT IS JUDGED: first to one recipient, then
// over growing waits, and only then is that recipient set aside.
ok('a failed batch is narrowed to its head',
	care.careSendAfterFailure(3, 1, 0), { act: 'isolate', waitMs: 2000 });
ok('however big it was',
	care.careSendAfterFailure(2, 1, 0).act, 'isolate');

// And then the same person, over waits that grow: two seconds only ever rode
// out a stutter, and the thing that fixes a KoL that has had too much through
// it in the last minute is a pause.
ok('then the same one again, after ten seconds',
	care.careSendAfterFailure(1, 2, 0), { act: 'again', waitMs: 10000 });
ok('and after thirty',
	care.careSendAfterFailure(1, 3, 0), { act: 'again', waitMs: 30000 });

// FOUR GOES AND THEN PAST THEM. This is the line that matters: the run
// carries on, which is the whole of COwliCK's requirement that sending must
// not "stop before all intended packages are sent".
ok('and then that one is set aside, not the run',
	care.careSendAfterFailure(1, 4, 0), { act: 'skip', waitMs: 0 });
ok('and a fifth attempt would be too, if it got there',
	care.careSendAfterFailure(1, 9, 0).act, 'skip');

// Set aside with others already set aside is still just a skip, until it is
// so many in a row that the recipients cannot be what they have in common.
ok('a second awkward clanmate is still only a skip',
	care.careSendAfterFailure(1, 4, 1).act, 'skip');
ok('and a third',
	care.careSendAfterFailure(1, 4, 2).act, 'skip');
ok('and a fourth',
	care.careSendAfterFailure(1, 4, 3).act, 'skip');
ok('the fifth in a row is not about the recipients any more',
	care.careSendAfterFailure(1, 4, 4), { act: 'stop', waitMs: 0 });

// A SKIP RESETS THE COUNT in the loop, so this only ever fires on five
// consecutive ones -- five scattered through two hundred recipients must not
// add up to a stop.
ok('a run of skips is what counts, and the loop clears it on any answer',
	care.careSendAfterFailure(1, 4, 0).act, 'skip');

// Narrowing never stops, whatever has gone before: a batch of three has not
// yet told anybody which of the three is the trouble, so it cannot be the
// evidence that there is no point carrying on.
ok('a batch is narrowed even when the run of skips is long',
	care.careSendAfterFailure(3, 1, 4).act, 'isolate');

/* ---- careSendGiveUpOn: a recipient KoL will not take at all ---- */

// A clanmate who has you on their ignore list cannot be sent a kmail or a
// gift, and nothing but a send can find that out. The send that finds it out
// aborts the endpoint and comes back as a 404, so without this the whole of
// careSendAfterFailure's narrowing and backing off is spent relearning it --
// three quarters of a minute, every run, for somebody who cannot be sent to.
//
// TWO AND NOT ONE, because a request can die for reasons that have nothing to
// do with whoever it happened to be sending to at the time.
var strikes = {};
ok('one failure is not enough to write somebody off',
	care.careSendGiveUpOn(strikes, 7000001), false);
ok('the second is', care.careSendGiveUpOn(strikes, 7000001), true);

// Counted per recipient, since the whole point is telling one unsendable
// clanmate apart from a bad minute.
var two = {};
care.careSendGiveUpOn(two, 111);
ok('somebody else starts from nothing', care.careSendGiveUpOn(two, 222), false);
ok('and their own second one counts', care.careSendGiveUpOn(two, 222), true);
ok('without disturbing the first', two[111], 1);

// AND ONLY FOR THE RUN. The tally is handed in rather than kept here, so a
// new run starts with a fresh one and tries everybody who is ticked --
// COwliCK's call, 2026-11-21: "forget", and "attempt the send to anybody who
// is ticked". A kept list would quietly stop being true the day somebody took
// him off their ignore list, and could never find out, having stopped trying.
ok('a fresh run has no memory of them',
	care.careSendGiveUpOn({}, 7000001), false);

if (failures > 0) {
	console.log(failures + ' failure(s)');
	process.exit(1);
}
console.log('all ok');
