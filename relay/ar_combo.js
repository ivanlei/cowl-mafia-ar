// ar_combo.js -- a box you type in with its list underneath it.
//
// WHY NOT <datalist>, which is what this replaced. A native datalist is one
// attribute and does the filtering for free, and in Safari -- which is where
// these pages are actually read -- it draws a small chevron button inside the
// right-hand edge of the field and opens its list from there. COwliCK,
// 2026-11-21: "the combobox for selecting things should have the dropdown
// below the textbox for the combo not beside it." Measured in a WebKit view
// before replacing it, and he is describing exactly what WebKit does.
//
// A native list also cannot be styled, cannot show a second column, and on a
// touch device is a system picker rather than part of the page.
//
// WHAT YOU TYPE IS STILL THE ANSWER. This is not a <select> in disguise: the
// Care Packages box has to accept an item you do not hold yet, because a
// package for two hundred people is something you go and buy. So the list
// only suggests, the input keeps whatever is typed, and the server is what
// decides whether it names a real item.
//
// THE LIST SITS OVER THE PAGE, not in it (position: absolute). A list that
// pushed the rows below it down would move the control you were about to
// reach for, every time you typed a letter.

(function () {
	'use strict';

	// HOW MANY ROWS TO DRAW AT ONCE. The suggestion list is every giftable
	// item the allowed places hold -- 1,921 of them on the character this was
	// written against -- and building two thousand divs on each keystroke is
	// a list that stutters as you type. Forty is more than fits on screen, so
	// the cap is never the reason you cannot see a match; the line underneath
	// says how many were left out, because silently showing a prefix of the
	// answer is how you conclude an item is missing.
	var SHOWN = 40;

	function matches(options, typed) {
		var want = typed.trim().toLowerCase();
		if (!want) return options.slice();
		var out = [];
		for (var i = 0; i < options.length; i++) {
			if (options[i].name.toLowerCase().indexOf(want) >= 0) out.push(options[i]);
		}
		return out;
	}

	function attach(input, getOptions) {
		var wrap = input.parentNode;
		if (!wrap || wrap.className.indexOf('ar-combo') < 0) return;

		// One list per box, so re-attaching a cloned row does not leave two.
		var old = wrap.querySelector('.ar-combo-list');
		if (old) wrap.removeChild(old);

		var list = document.createElement('div');
		list.className = 'ar-combo-list';
		list.hidden = true;
		wrap.appendChild(list);

		var showing = [];
		var active = -1;

		function close() {
			list.hidden = true;
			active = -1;
		}

		function mark() {
			var rows = list.querySelectorAll('.ar-combo-item');
			for (var i = 0; i < rows.length; i++) {
				if (i === active) {
					rows[i].className = 'ar-combo-item ar-combo-on';
					// Only when it is off screen: scrollIntoView on every
					// keypress fights the mouse if you are hovering the list.
					var r = rows[i].getBoundingClientRect();
					var box = list.getBoundingClientRect();
					if (r.top < box.top) rows[i].scrollIntoView(true);
					else if (r.bottom > box.bottom) rows[i].scrollIntoView(false);
				} else {
					rows[i].className = 'ar-combo-item';
				}
			}
		}

		function take(option) {
			input.value = option.name;
			close();
			// The page's own save hangs off change, and setting .value from
			// script does not fire one.
			input.dispatchEvent(new Event('change', { bubbles: true }));
		}

		function draw() {
			var all = matches(getOptions() || [], input.value);
			showing = all.slice(0, SHOWN);
			active = -1;
			list.textContent = '';

			if (!all.length) {
				var none = document.createElement('div');
				none.className = 'ar-combo-none';
				// NOT AN ERROR. You are allowed to name something you do not
				// hold -- that is the whole difference between this and a
				// select -- so this says what the list knows, not what you
				// may type.
				none.textContent = 'Nothing you hold matches. You can still type a name.';
				list.appendChild(none);
			}

			showing.forEach(function (option, i) {
				var row = document.createElement('div');
				row.className = 'ar-combo-item';

				var name = document.createElement('span');
				name.textContent = option.name;
				row.appendChild(name);

				if (option.have !== undefined && option.have !== null) {
					var have = document.createElement('span');
					have.className = 'ar-combo-have';
					// KoL's own select writes the count after the name the
					// same way: "11-leaf clover (231)".
					have.textContent = '(' + option.have + ')';
					row.appendChild(have);
				}

				// MOUSEDOWN AND NOT CLICK. A click fires after blur, and blur
				// closes the list -- so by the time a click arrived the row
				// it was aimed at no longer existed, and picking with the
				// mouse did nothing at all.
				row.addEventListener('mousedown', function (event) {
					event.preventDefault();
					take(option);
				});
				row.addEventListener('mouseenter', function () {
					active = i;
					mark();
				});
				list.appendChild(row);
			});

			if (all.length > showing.length) {
				var more = document.createElement('div');
				more.className = 'ar-combo-none';
				more.textContent = 'and ' + (all.length - showing.length)
					+ ' more — keep typing';
				list.appendChild(more);
			}

			list.hidden = false;
			list.scrollTop = 0;
		}

		// THE WHOLE LIST ON FOCUS, not what matches what is already in the
		// box. A row you come back to holds the item you picked last time, so
		// narrowing by it would offer that one entry out of two thousand --
		// which is useless exactly when you are trying to change it.
		input.addEventListener('focus', function () {
			var all = getOptions() || [];
			showing = all.slice(0, SHOWN);
			active = -1;
			list.textContent = '';
			var typed = input.value;
			input.value = '';
			draw();
			input.value = typed;
		});

		input.addEventListener('input', draw);

		input.addEventListener('blur', function () {
			// No delay needed: the rows take themselves on mousedown, which
			// happens before blur.
			close();
		});

		input.addEventListener('keydown', function (event) {
			if (event.key === 'Escape') {
				close();
				return;
			}
			if (event.key === 'ArrowDown' || event.key === 'ArrowUp') {
				if (list.hidden) {
					draw();
					return;
				}
				if (!showing.length) return;
				event.preventDefault();
				active += event.key === 'ArrowDown' ? 1 : -1;
				if (active < 0) active = showing.length - 1;
				if (active >= showing.length) active = 0;
				mark();
				return;
			}
			if (event.key === 'Enter') {
				// ENTER IS THE PAGE'S UNLESS YOU HAVE ARROWED INTO THE LIST.
				// Typing a name in full and pressing Enter should save the
				// row, not silently swap in whichever suggestion happened to
				// be first.
				if (!list.hidden && active >= 0 && showing[active]) {
					event.preventDefault();
					take(showing[active]);
				} else {
					close();
				}
			}
		});
	}

	// THE HATCH COMES FIRST AND RETURNS, the same shape ar_care.js uses.
	// .github/check.py runs tests/*.test.js with a plain `node <file>`, where
	// there is no `window` at all -- so touching it before this point is a
	// ReferenceError and the test cannot even load the file.
	if (typeof module !== 'undefined' && module.exports) {
		module.exports = { matches: matches, SHOWN: SHOWN };
		return;
	}

	window.arCombo = { attach: attach, matches: matches, SHOWN: SHOWN };
})();
