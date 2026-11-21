// tests/ar_combo.test.js -- the combo box's filtering.
//
// WHY THIS AND NOT THE DOM. ar_combo.js is mostly keyboard and mouse
// handling, which needs a browser; matches() is the one part that decides
// anything, and it decides the thing a suggestion list lives or dies by. Two
// thousand items on this character means the difference between a substring
// match and a prefix match is the difference between finding "11-leaf clover"
// by typing "clover" and not finding it at all.
//
// Run by .github/check.py with a plain `node <file>`, like every other test
// here, so there is nothing asynchronous in it.

var assert = require('assert');
var combo = require('../relay/ar_combo.js');

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

function names(list) {
	return list.map(function (o) { return o.name; });
}

// Real names off the character this was written against, including the four
// with a comma in them and one that only matches in the middle.
var HELD = [
	{ name: '11-leaf clover', have: 231 },
	{ name: 'clove incense', have: 30 },
	{ name: 'disassembled clover', have: 2 },
	{ name: 'Oh, the Humanitini', have: 1 },
	{ name: 'ten-leaf clover', have: 2 },
	{ name: 'soda water', have: 0 }
];

/* ---- matches ---- */

// A SUBSTRING, NOT A PREFIX, which is the whole decision. KoL's item names
// put the distinguishing word last about as often as first -- "11-leaf
// clover", "disassembled clover" -- so a prefix match finds neither of them
// from the word you actually have in mind.
ok('finds a word in the middle of a name',
	names(combo.matches(HELD, 'clover')),
	['11-leaf clover', 'disassembled clover', 'ten-leaf clover']);

ok('finds by the start as well',
	names(combo.matches(HELD, '11-leaf')), ['11-leaf clover']);

ok('ignores case',
	names(combo.matches(HELD, 'OH, THE')), ['Oh, the Humanitini']);

// A comma in what you type is just a character: these names really do have
// one, and the box is not a comma-separated list.
ok('a comma typed is part of the name, not a separator',
	names(combo.matches(HELD, ', the')), ['Oh, the Humanitini']);

ok('surrounding spaces are ignored',
	names(combo.matches(HELD, '  incense ')), ['clove incense']);

// EMPTY SHOWS EVERYTHING, which is what focusing an empty box does. Returning
// nothing here would mean a box you have not typed in yet looks like a box
// with no suggestions at all.
ok('empty shows the whole list', combo.matches(HELD, '').length, HELD.length);
ok('and so does whitespace', combo.matches(HELD, '   ').length, HELD.length);

// A COPY, not the array itself: the caller slices it to the display cap and
// must not be able to shorten what the page holds.
var all = combo.matches(HELD, '');
all.length = 1;
ok('the empty case hands back a copy', HELD.length, 6);

ok('no match is an empty list, not everything',
	names(combo.matches(HELD, 'zzzz')), []);

/* ---- pickable, and what cannot be sent ---- */

// WHAT THIS IS FOR. The item list used to leave out anything that could not
// be gifted, so typing the name of something held came back as "Nothing you
// hold matches" -- which is false, and on this character it is false for 262
// of the display case and 279 of the inventory. COwliCK, 2026-11-21: "the
// combo to select items to send doesn't seem to like what's in closet or DC."
// They are rows now, marked, and the only thing they will not do is be
// picked.
var MIXED = [
	{ name: 'Epic Weapon', have: 1, gift: false },
	{ name: '11-leaf clover', have: 231, gift: true },
	{ name: 'quest clover of some kind', have: 1, gift: false },
	{ name: 'disassembled clover', have: 2, gift: true }
];

// A ROW WITH NO FLAG IS PICKABLE, which is what keeps this safe for the
// Anti-Raffle's ticket box: it sends no `gift` at all and every row of it is
// an offer.
ok('no flag means pickable', combo.pickable({ name: 'x' }), true);
ok('true means pickable', combo.pickable({ name: 'x', gift: true }), true);
ok('only false is not', combo.pickable({ name: 'x', gift: false }), false);

// SENDABLE FIRST, AND THAT IS NOT COSMETIC. The list is cut to SHOWN, so an
// unsendable row does not merely clutter -- it can push the item you were
// looking for off the bottom and out of sight.
ok('the sendable ones come first',
	names(combo.matches(MIXED, 'clover')),
	['11-leaf clover', 'disassembled clover', 'quest clover of some kind']);

ok('and with nothing typed, too',
	names(combo.matches(MIXED, '')),
	['11-leaf clover', 'disassembled clover', 'Epic Weapon', 'quest clover of some kind']);

// Both groups keep the order they arrived in, so this is a partition and not
// a sort: the server decides what order items are offered in.
ok('each group keeps the order it came in',
	names(combo.matches([
		{ name: 'b', gift: true }, { name: 'z', gift: false },
		{ name: 'a', gift: true }, { name: 'y', gift: false }
	], '')),
	['b', 'a', 'z', 'y']);

// AND THEY ARE STILL FOUND. The point of listing them is that a name you own
// gets an answer, so a search that matches only unsendable things must come
// back with them rather than with nothing.
ok('something held but unsendable is still a match',
	names(combo.matches(MIXED, 'epic')), ['Epic Weapon']);
ok('and is not mistaken for nothing',
	combo.matches(MIXED, 'epic').length > 0, true);

if (failures > 0) {
	console.log(failures + ' failure(s)');
	process.exit(1);
}
console.log('all ok');
