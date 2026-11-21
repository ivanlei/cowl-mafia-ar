// tests/ar_ask.test.js -- the contract every endpoint call on both pages keeps.
//
// WHY THIS FILE EXISTS, and it is one bug rather than a wish for coverage.
// ask(url, params, then, always) reads at the call site like a success
// callback and a failure callback, and `always` is not one: it runs down every
// path, the answer included. Four call sites wanted "only when it failed";
// three of them set a flag inside `then` and checked it in `always`; the
// fourth -- the Care Packages send -- did not, and so printed
//
//     Stopped after 15 sent. Reload to see where it got to.
//
// after a batch that had just sent three packages perfectly, cleared the
// page's `sending` flag mid-send, and said it again at 18 and at 27, because
// `then` had already queued the next batch and nothing had stopped at all.
// COwliCK found it while sending to a real clan.
//
// The fix is that `always` is told which path it is on -- always(ok, why) --
// so no caller has to reconstruct it. These checks pin both halves of that:
// that ok is true on exactly one path and false on the other four, and that
// `why` is the same sentence the page was shown, since a caller that wants to
// say "that batch again, because X" should not have to read X back out of the
// DOM.
//
// XMLHttpRequest IS STUBBED, and that is the whole reason this is testable at
// all: ar_ask.js builds its request, hands it to the browser, and does all
// five of its decisions inside onreadystatechange. A stub that lets a test
// choose the status and the body reaches every one of them in a plain `node
// <file>`, which is how .github/check.py runs these.

var assert = require('assert');

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

// --- the stub ---------------------------------------------------------------

var sent;   // the last request body, so the password hash can be checked too

function stubXHR(status, body) {
	global.XMLHttpRequest = function () {
		var self = this;
		this.readyState = 0;
		this.status = 0;
		this.responseText = '';
		this.open = function () {};
		this.setRequestHeader = function () {};
		this.send = function (form) {
			sent = form;
			self.readyState = 4;
			self.status = status;
			self.responseText = body;
			self.onreadystatechange();
		};
	};
}

var ask = require('../relay/ar_ask.js');

// One call, with every path's outcome collected. The status and the body are
// already in the stub by the time this runs; at() below is the pair.
function call(params) {
	var said = [];
	var answered = null;
	var always = null;
	var run = ask.make('HASH', function (text, kind) { said.push([text, kind]); });
	run('/x.ash', params || {}, function (answer) {
		answered = answer;
	}, function (good, why) {
		// The arguments exactly as a caller sees them, so a change to the
		// contract shows up here rather than in whichever page breaks first.
		always = { ok: good, why: why };
	});
	return { said: said, answered: answered, always: always };
}

function at(status, body, params) {
	stubXHR(status, body);
	return call(params);
}

/* ---- the one path that reaches the answer ---- */

var good = at(200, '{"ok":true,"error":"","done":[{"who":1}]}');
ok('an answer reaches `then`', good.answered.done.length, 1);
ok('and `always` is told it did', good.always.ok, true);
ok('with nothing to explain', good.always.why, '');
ok('and nothing is said to the page', good.said.length, 0);

/* ---- and the four that do not ---- */

// A stale password hash. KoLmafia answers this itself, before the script runs,
// so there is no {ok:false} to read.
var stale = at(401, '');
ok('a 401 does not reach `then`', stale.answered, null);
ok('`always` is told so', stale.always.ok, false);
ok('and is handed the sentence the page was shown', stale.always.why,
	'This page is out of date. Reload it.');
ok('which is the sentence the page was shown', stale.said[0][0],
	'This page is out of date. Reload it.');
ok('as an error', stale.said[0][1], 'err');

var dead = at(0, '');
ok('a request that did not arrive', dead.always.ok, false);
ok('names the status, since 0 and 500 are different problems', dead.always.why,
	'KoLmafia did not answer (0).');

// AN ASH SCRIPT THAT WILL NOT COMPILE IS SERVED AS A BARE 404 of one byte, and
// one that aborts halfway leaves a part-written answer. Both parse as nothing,
// which is why this path is not theoretical.
var junk = at(200, '{"ok":true,"done":[');
ok('a truncated answer', junk.always.ok, false);
ok('and says that is what it was', junk.always.why,
	'KoLmafia answered with something that is not an answer.');
ok('and `then` never saw it', junk.answered, null);

// The endpoint's own refusal, in its own words -- which is the path the send's
// guards take, so the wording has to survive to the caller intact.
var no = at(200, '{"ok":false,"error":"Could not read your sent mail, so there is no telling who has already had one."}');
ok('a refusal', no.always.ok, false);
ok('keeps the endpoint\'s own words', no.always.why,
	'Could not read your sent mail, so there is no telling who has already had one.');
ok('and does not reach `then`', no.answered, null);

// An {ok:false} with no sentence at all still has to leave something readable:
// a caller that prints `why` must not print "undefined".
var bare = at(200, '{"ok":false}');
ok('a refusal with no reason still has one', bare.always.why, 'Refused.');

/* ---- the request itself ---- */

at(200, '{"ok":true}', { to: '1,2,3', note: 'a & b' });
ok('the hash goes with every call', sent.indexOf('pwd=HASH') === 0, true);
ok('and the parameters are encoded, not interpolated',
	sent.indexOf('to=1%2C2%2C3') > 0, true);
ok('including the ones with an ampersand in them',
	sent.indexOf('note=a%20%26%20b') > 0 || sent.indexOf('note=a+%26+b') > 0, true);

if (failures > 0) {
	console.log(failures + ' failure(s)');
	process.exit(1);
}
console.log('all ok');
