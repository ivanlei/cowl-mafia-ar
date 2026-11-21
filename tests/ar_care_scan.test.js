// tests/ar_care_scan.test.js -- the Care Packages scan loop's stopping rules.
//
// WHY THESE AND NOT THE DOM. The loop asks ar_care_scan.ash for a batch,
// waits, and asks again, and the only two ways that can be seriously wrong are
// the ends: a loop that will not stop keeps asking KoL for profiles with
// nobody watching, and a loop that stops early leaves half the clan unread
// while the page says it finished. Both of those live in careScanNext(), which
// is why it is a pure function with nothing of the browser in it.
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

/* ---- careScanNext: when to ask for another batch ---- */

// The first batch has no `fetched` to judge, because nothing has been fetched.
// Treating a missing count as "no progress" would mean the scan never took its
// first step -- the button would appear to do nothing at all.
ok('goes, before any batch has run',
	care.careScanNext({ todo: 216, fetched: null, stopped: false }), 'go');
ok('goes, before any batch has run (undefined rather than null)',
	care.careScanNext({ todo: 216, fetched: undefined, stopped: false }), 'go');

ok('goes while a batch fetched something and work remains',
	care.careScanNext({ todo: 100, fetched: 5, stopped: false }), 'go');

ok('done when nothing is left',
	care.careScanNext({ todo: 0, fetched: 5, stopped: false }), 'done');
// A queue cannot really go negative, but "todo <= 0" rather than "=== 0" is
// what keeps a miscount from becoming an endless loop.
ok('done when the count has gone past zero',
	care.careScanNext({ todo: -1, fetched: 5, stopped: false }), 'done');

// STOP BEATS EVERYTHING, including a batch that just fetched five profiles.
// The press happens between batches, so the only place it can be honoured is
// here, before the next request goes out.
ok('stopped beats work remaining',
	care.careScanNext({ todo: 100, fetched: 5, stopped: true }), 'stopped');
ok('stopped beats being done',
	care.careScanNext({ todo: 0, fetched: 5, stopped: true }), 'stopped');

// NO PROGRESS MEANS STOP. A profile request that does not bring back a profile
// is deliberately not cached (careLooksLikeProfile in ar_care.ash), so the
// member stays in the queue -- and without this the loop would ask for the
// same five profiles for ever.
ok('stalled when a batch fetched nothing and work remains',
	care.careScanNext({ todo: 100, fetched: 0, stopped: false }), 'stalled');

/* ---- careEta: how long is left ---- */

// Before anything has been fetched the only rate available is the measured
// one from the old page: ~100ms a profile, plus each profile's share of its
// batch's pause (1000ms over 5 is 200ms). 10 profiles at 300ms is 3s.
ok('estimates from the measured rate before a batch has been timed',
	care.careEta({ todo: 10, batch: 5, pause: 1000, fetchedSoFar: 0, elapsedMs: 0 }), 3);

// Once a scan has timed itself, its own rate is used -- 20 profiles in 4s is
// 200ms each -- and THE PAUSE IS NOT ADDED AGAIN. Elapsed time already spans
// the pauses, and the first version of this charged for them twice: on a real
// 239-member scan it claimed 86 seconds left when 50 were left.
ok('estimates from the observed rate, without charging the pause twice',
	care.careEta({ todo: 10, batch: 5, pause: 1000, fetchedSoFar: 20, elapsedMs: 4000 }), 2);

ok('nothing left is no time left',
	care.careEta({ todo: 0, batch: 5, pause: 1000, fetchedSoFar: 20, elapsedMs: 4000 }), 0);
ok('a negative queue is no time left, not negative time',
	care.careEta({ todo: -3, batch: 5, pause: 1000, fetchedSoFar: 20, elapsedMs: 4000 }), 0);

// A batch of zero would divide by zero into Infinity batches of pause; the
// floor of 1 is what keeps an estimate a number.
ok('a batch of zero still gives a number',
	care.careEta({ todo: 4, batch: 0, pause: 0, fetchedSoFar: 0, elapsedMs: 0 }), 1);

// No pause asked for is no pause added -- the "as fast as it answers" setting.
ok('no pause is not counted as one',
	care.careEta({ todo: 10, batch: 5, pause: 0, fetchedSoFar: 20, elapsedMs: 4000 }), 2);

/* ---- careProgressText ---- */

ok('says how far it has got, and how long is left',
	care.careProgressText({
		todo: 131, batch: 5, pause: 1000, fetchedSoFar: 85, elapsedMs: 8500
	}),
	// 85 profiles in 8.5s is 100ms each, pauses included, so 131 left is 14s.
	'looked up 85 of 216 · about 14 seconds left');

// COUNTED AGAINST WHAT THE SCAN OWES, not against the roster. The endpoint's
// own `done` is the roster minus the queue, so a scan that had fetched nothing
// opened with "looked up 26 of 239" -- you, the inactive accounts and anyone
// already sent to, none of whom is ever fetched. Measured on a live scan
// before this was changed.
ok('starts at nothing looked up, whatever the endpoint counts as done',
	care.careProgressText({
		done: 26, total: 239, todo: 213, batch: 5, pause: 1000,
		fetchedSoFar: 0, elapsedMs: 0
	}),
	'looked up 0 of 213 · about 64 seconds left');

// No estimate once there is nothing left to wait for: "about 0 seconds left"
// next to a finished scan reads as a stuck page.
ok('drops the estimate when there is nothing left',
	care.careProgressText({
		todo: 0, batch: 5, pause: 1000, fetchedSoFar: 216, elapsedMs: 60000
	}),
	'looked up 216 of 216');

ok('a single second is singular',
	care.careProgressText({
		todo: 1, batch: 5, pause: 0, fetchedSoFar: 215, elapsedMs: 215
	}),
	'looked up 215 of 216 · about 1 second left');

if (failures > 0) {
	console.log(failures + ' failure(s)');
	process.exit(1);
}
console.log('all ok');
