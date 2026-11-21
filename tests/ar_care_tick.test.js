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

if (failures > 0) {
	console.log(failures + ' failure(s)');
	process.exit(1);
}
console.log('all ok');
