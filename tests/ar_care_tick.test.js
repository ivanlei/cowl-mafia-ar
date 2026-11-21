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

if (failures > 0) {
	console.log(failures + ' failure(s)');
	process.exit(1);
}
console.log('all ok');
