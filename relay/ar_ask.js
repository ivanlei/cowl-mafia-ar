// ar_ask.js -- how both of this repository's pages talk to their endpoints.
//
// Every endpoint here answers {"ok":..,"error":".."} and then whatever it is
// for, so there is one way to tell a refusal from an answer and never a reason
// to guess from an HTTP status. The four ways that can go wrong are all handled
// in one place below, and each of them was met in a relay browser rather than
// imagined:
//
//   401 and empty      a stale password hash. KoLmafia answers that itself
//                      (RelayAgent), before the script runs at all, so there
//                      is no {ok:false} to read -- the page has to know that
//                      an empty 401 means "reload me".
//   any other non-200  KoLmafia is not answering.
//   not JSON           an ASH script that will not compile is served as a bare
//                      404, and one that aborts halfway leaves a part-written
//                      answer. Both parse as nothing.
//   ok:false           the endpoint refused, and said why in its own words.
//
// LIVED IN ar_relay.js UNTIL THE CARE PAGE NEEDED IT (2026-11-21). Loading
// that file to get at it was not an option -- it is the whole Anti-Raffle
// application and starts itself on DOMContentLoaded -- and a second copy of
// four error paths in the second page is the kind of duplicate that rots one
// side at a time. So it moved here and both pages load it.
//
// A FACTORY RATHER THAN A FUNCTION, because the one thing the two pages do not
// share is where a message goes: the Anti-Raffle has a #ar-note, the Care
// Packages page has a line under its buttons. So each page hands in its own
// say(text, kind) and its own password hash, and gets back an ask() that
// reports through it.

(function () {
	'use strict';

	function make(pwd, say) {
		return function ask(url, params, then, always) {
			var form = 'pwd=' + encodeURIComponent(pwd);
			for (var key in params) {
				if (!params.hasOwnProperty(key)) continue;
				form += '&' + encodeURIComponent(key) + '=' + encodeURIComponent(params[key]);
			}

			var xhr = new XMLHttpRequest();
			// POST throughout, including the reads: a GET of a relay script is
			// a thing a browser may repeat on its own, and one of these
			// restocks a store.
			xhr.open('POST', url, true);
			xhr.setRequestHeader('Content-Type', 'application/x-www-form-urlencoded');
			xhr.onreadystatechange = function () {
				if (xhr.readyState !== 4) return;

				// `always` runs down every path, so a caller that disabled a
				// button can put it back whether the answer was yes, no or
				// nothing at all.
				if (xhr.status === 401) {
					say('This page is out of date. Reload it.', 'err');
					if (always) always();
					return;
				}
				if (xhr.status !== 200) {
					say('KoLmafia did not answer (' + xhr.status + ').', 'err');
					if (always) always();
					return;
				}

				var answer;
				try {
					answer = JSON.parse(xhr.responseText);
				} catch (e) {
					say('KoLmafia answered with something that is not an answer.', 'err');
					if (always) always();
					return;
				}
				if (!answer.ok) {
					say(answer.error || 'Refused.', 'err');
					if (always) always();
					return;
				}
				then(answer);
				if (always) always();
			};
			xhr.send(form);
		};
	}

	if (typeof module !== 'undefined' && module.exports) {
		module.exports = { make: make };
		return;
	}

	window.arAsk = { make: make };
})();
