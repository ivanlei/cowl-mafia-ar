// ar_relay.js -- the Anti-Raffle page.
//
// Vanilla, and deliberately so: this repository ships one page, and a page
// that pulls a framework off a CDN is a page that stops working the day the
// CDN does, on an iPad in a relay browser where there is nothing to debug it
// with. Everything below is DOM calls that have worked since well before the
// browsers KoL's relay runs in.
//
// Four endpoints, all answering {ok, error, ...}:
//
//   ar_items.ash   search, add, remove, and the chosen list
//   ar_stock.ash   restock -- the only one that changes anything
//   ar_sales.ash   the store's sales log
//   ar_prefs.ash   the settings, allowlisted server-side
//
// Text goes into the page through textContent, never innerHTML, because an
// item name and a buyer's name are both things other people chose.

(function () {
	'use strict';

	var SEARCH_WAIT = 250;     // ms of quiet before a search goes out
	var SEARCH_MIN = 3;        // ar_items.ash refuses shorter, so don't ask

	var state = {
		settings: null,
		items: [],
		sales: [],
		buyers: [],
		names: [],
		filterItem: '',
		filterBuyer: '',
		// Newest first, which is the order the store log arrives in and the
		// order you read a winner out of it.
		sortBy: 'when',
		sortDesc: true,
		loaded: {}             // which tabs have asked for their data
	};

	// --- Talking to KoLmafia ---------------------------------------------

	function say(text, kind) {
		var note = document.getElementById('ar-note');
		note.textContent = text || '';
		note.className = kind || '';
	}

	function ask(url, params, then, always) {
		var form = 'pwd=' + encodeURIComponent(arPwd);
		for (var key in params) {
			if (!params.hasOwnProperty(key)) continue;
			form += '&' + encodeURIComponent(key) + '=' + encodeURIComponent(params[key]);
		}

		var xhr = new XMLHttpRequest();
		// POST throughout, including the reads: a GET of a relay script is a
		// thing a browser may repeat on its own, and one of these restocks.
		xhr.open('POST', url, true);
		xhr.setRequestHeader('Content-Type', 'application/x-www-form-urlencoded');
		xhr.onreadystatechange = function () {
			if (xhr.readyState !== 4) return;

			// KoLmafia answers a stale password hash with an empty 401 before
			// the script runs at all, so there is no {ok:false} to read.
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
				// An ASH script that will not compile is served as a bare 404,
				// and one that aborts halfway leaves a part-written answer.
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
	}

	// --- Small builders ---------------------------------------------------

	function el(tag, className, text) {
		var node = document.createElement(tag);
		if (className) node.className = className;
		if (text !== undefined && text !== null) node.textContent = String(text);
		return node;
	}

	function icon(image) {
		if (!image) return el('span');
		var img = document.createElement('img');
		img.className = 'icon';
		img.src = '/images/itemimages/' + image;
		img.alt = '';
		return img;
	}

	function meat(n) {
		// KoL's own grouping, so a parked price reads as the wall it is.
		return String(n).replace(/\B(?=(\d{3})+(?!\d))/g, ',');
	}

	// A heading with a `key` is one you can sort by: clicking it sorts, and
	// clicking the one already sorted turns it round. `onSort` is what the
	// caller does with the new order, since the table itself holds no rows.
	function table(headings, sorted, onSort) {
		var t = el('table', 'ar');
		var head = el('tr');
		for (var i = 0; i < headings.length; i++) {
			var heading = headings[i];
			var h = el('th', heading.num ? 'num' : null, heading.text);
			if (heading.key && onSort) {
				h.className = (h.className ? h.className + ' ' : '') + 'ar-sortable';
				if (sorted && sorted.by === heading.key) {
					h.className += ' on';
					// An arrow rather than a word: the column is narrow and the
					// heading is already as short as it reads.
					h.appendChild(el('span', 'ar-arrow', sorted.desc ? ' \u25bc' : ' \u25b2'));
				}
				h.onclick = (function (key) {
					return function () { onSort(key); };
				})(heading.key);
			}
			head.appendChild(h);
		}
		t.appendChild(head);
		return t;
	}

	function cell(row, text, className) {
		var td = el('td', className, text);
		row.appendChild(td);
		return td;
	}

	// --- Tickets ----------------------------------------------------------

	function drawChosen() {
		var where = document.getElementById('ar-chosen');
		where.textContent = '';

		if (!state.items.length) {
			where.appendChild(el('p', 'ar-dim',
				'No tickets chosen yet. Find an item above, or use `ar add <item>` in the gCLI.'));
			return;
		}

		var t = table([
			{ text: '' }, { text: 'Ticket' },
			{ text: 'Mall', num: true }, { text: 'Min', num: true },
			{ text: 'In store', num: true }, { text: '' }
		]);

		state.items.forEach(function (row) {
			var tr = el('tr');
			tr.appendChild(el('td')).appendChild(icon(row.image));

			var name = el('td');
			name.appendChild(el('span', null, row.name));
			name.appendChild(document.createTextNode(' '));
			name.appendChild(el('span', 'ar-id', '[id:' + row.id + ']'));
			tr.appendChild(name);

			cell(tr, row.tradeable ? meat(row.mallPrice) : '—', 'num');
			cell(tr, meat(row.minPrice), 'num');
			cell(tr, row.inStore + ' of ' + row.want, 'num');

			var act = el('td');
			var drop = el('button', 'ar-go', 'Remove');
			drop.onclick = function () {
				say('Removing ' + row.name + '…', 'busy');
				ask('/ar_items.ash', { remove: row.id }, function (answer) {
					state.items = answer.items;
					state.settings = answer.settings;
					drawChosen();
					say(row.name + ' is no longer a ticket.', 'done');
				});
			};
			act.appendChild(drop);
			tr.appendChild(act);

			t.appendChild(tr);
		});

		where.appendChild(t);
	}

	function drawFound(answer) {
		var where = document.getElementById('ar-found');
		where.textContent = '';

		if (!answer.found.length) {
			where.appendChild(el('p', 'ar-dim', 'Nothing matches that.'));
			return;
		}

		if (answer.total > answer.shown) {
			where.appendChild(el('p', 'ar-dim',
				'Showing ' + answer.shown + ' of ' + answer.total + '. Type more to narrow it.'));
		}

		var t = table([
			{ text: '' }, { text: 'Item' }, { text: 'Min', num: true }, { text: '' }
		]);

		answer.found.forEach(function (found) {
			var tr = el('tr');
			tr.appendChild(el('td')).appendChild(icon(found.image));

			var name = el('td');
			name.appendChild(el('span', null, found.name));
			name.appendChild(document.createTextNode(' '));
			name.appendChild(el('span', 'ar-id', '[id:' + found.id + ']'));
			if (!found.tradeable) {
				name.appendChild(document.createTextNode(' '));
				name.appendChild(el('span', 'ar-shut', 'not tradeable'));
			}
			tr.appendChild(name);

			cell(tr, meat(found.minPrice), 'num');

			var act = el('td');
			if (found.chosen) {
				act.appendChild(el('span', 'ar-dim', 'chosen'));
			} else {
				var add = el('button', 'ar-go', 'Use as ticket');
				add.onclick = function () {
					say('Adding ' + found.name + '…', 'busy');
					ask('/ar_items.ash', { add: found.id }, function (got) {
						state.items = got.items;
						state.settings = got.settings;
						found.chosen = true;
						add.parentNode.textContent = 'chosen';
						add.parentNode.className = 'ar-dim';
						drawChosen();
						say(found.name + ' is now a ticket.', 'done');
					});
				};
				act.appendChild(add);
			}
			tr.appendChild(act);

			t.appendChild(tr);
		});

		where.appendChild(t);
	}

	var searchTimer = null;

	function searchSoon() {
		if (searchTimer) clearTimeout(searchTimer);
		searchTimer = setTimeout(function () {
			searchTimer = null;
			var q = document.getElementById('ar-q').value;
			if (q.replace(/^\s+|\s+$/g, '').length < SEARCH_MIN) {
				document.getElementById('ar-found').textContent = '';
				return;
			}
			say('Searching…', 'busy');
			ask('/ar_items.ash', { q: q }, function (answer) {
				say('');
				drawFound(answer);
			});
		}, SEARCH_WAIT);
	}

	// --- Settings ---------------------------------------------------------

	function setPref(name, value, then) {
		say('Saving…', 'busy');
		ask('/ar_prefs.ash', { name: name, value: value }, function (answer) {
			state.settings = answer.settings;
			say('Saved.', 'done');
			if (then) then();
		});
	}

	function drawSettings() {
		var where = document.getElementById('ar-settings');
		where.textContent = '';
		var s = state.settings;
		if (!s) return;

		var line = el('div');

		var countLabel = el('label', null, 'Stock ');
		var count = document.createElement('input');
		count.type = 'number';
		count.min = '1';
		count.value = s.count;
		count.onchange = function () {
			setPref('arRestockCount', count.value, function () { loadStock(true); });
		};
		countLabel.appendChild(count);
		countLabel.appendChild(document.createTextNode(' of each'));
		line.appendChild(countLabel);

		var parkLabel = el('label', null, 'Parked at ');
		var park = document.createElement('input');
		park.className = 'ar-price';
		park.type = 'number';
		park.min = '1';
		park.max = String(s.parkMax);
		park.value = s.parkPrice;
		park.onchange = function () {
			setPref('arParkPrice', park.value, function () { loadStock(true); });
		};
		parkLabel.appendChild(park);
		line.appendChild(parkLabel);

		where.appendChild(line);

		var sources = el('div', 'ar-sources');
		sources.appendChild(el('span', null, 'Restock from: '));
		s.sources.forEach(function (source) {
			var label = el('label');
			var box = document.createElement('input');
			box.type = 'checkbox';
			box.checked = source.enabled;
			box.onchange = function () {
				var on = [];
				var boxes = sources.querySelectorAll('input[type=checkbox]');
				for (var i = 0; i < boxes.length; i++) {
					if (boxes[i].checked) on.push(s.sources[i].place);
				}
				if (!on.length) {
					box.checked = true;
					say('Leave at least one source on.', 'err');
					return;
				}
				setPref('arSources', on.join(','), function () { loadStock(true); });
			};
			label.appendChild(box);
			label.appendChild(document.createTextNode(' ' + source.place));
			sources.appendChild(label);
		});
		where.appendChild(sources);

		// Only what KoL is stopping you doing today, and only when it is
		// stopping you. This is not about the checkboxes above -- those are
		// which sources you allow -- and in ordinary play none of it can fire,
		// so saying "every source is open" every time said nothing at all.
		// Which source is shut for a given ticket is on that ticket's row.
		var bits = [];
		if (s.limited) bits.push('limit mode: ' + s.limited);
		if (!s.caseOpen) bits.push('the display case will not open in Ronin');
		if (s.pulls === 0) bits.push('no pulls left today');
		if (bits.length) {
			where.appendChild(el('div', 'ar-note', bits.join(' · ')));
		}
	}

	// --- Stock ------------------------------------------------------------

	function drawStock() {
		var where = document.getElementById('ar-stock');
		where.textContent = '';

		if (!state.items.length) {
			where.appendChild(el('p', 'ar-dim', 'No tickets chosen yet.'));
			return;
		}

		var t = table([
			{ text: '' }, { text: 'Ticket' }, { text: 'In store' },
			{ text: 'Need', num: true }, { text: 'You have', num: true },
			{ text: 'In' }, { text: '' }
		]);

		state.items.forEach(function (row) {
			var tr = el('tr');
			tr.appendChild(el('td')).appendChild(icon(row.image));
			cell(tr, row.name);

			var store = el('td');
			if (!row.inStore) {
				store.appendChild(el('span', 'ar-dim', 'none'));
			} else {
				store.appendChild(document.createTextNode(
					row.inStore + ' @ ' + meat(row.storePrice)
					+ (row.storeLimit ? ' limit ' + row.storeLimit : '')));
				if (row.parked) {
					store.appendChild(document.createTextNode(' '));
					store.appendChild(el('span', 'ar-parked', 'parked'));
				}
			}
			tr.appendChild(store);

			cell(tr, row.shortfall || '—', row.shortfall ? 'num ar-short' : 'num');
			cell(tr, row.reachable, 'num');

			// One place per line. Strung together with separators they read as
			// one sentence about one number, which is the opposite of what
			// four places holding four different counts is.
			var from = el('td');
			var said = 0;
			row.sources.forEach(function (source) {
				if (!source.enabled) return;
				if (!source.available) return;
				var text = source.place + ': ' + source.available
					+ (source.shut ? ' (' + source.shut + ')' : '');
				from.appendChild(el('div', source.shut ? 'ar-shut' : null, text));
				said++;
			});
			if (!said) from.appendChild(el('span', 'ar-dim', 'nothing to hand'));
			tr.appendChild(from);

			var act = el('td');
			var one = el('button', 'ar-go ar-write', 'Restock');
			one.onclick = function () { restock(row.id, one); };
			act.appendChild(one);
			tr.appendChild(act);

			t.appendChild(tr);
		});

		// One above and one below. A long list of tickets put the only way to
		// restock all of them off the bottom of the screen, which on an iPad
		// means scrolling past every row to reach the button that acts on all
		// of them.
		where.appendChild(everyTicketButton());
		where.appendChild(t);
		where.appendChild(everyTicketButton());
	}

	function everyTicketButton() {
		var all = el('button', 'ar-go ar-write', 'Restock every ticket');
		all.onclick = function () { restock('', all); };
		var holder = el('p', 'ar-all');
		holder.appendChild(all);
		return holder;
	}

	function drawSteps(results) {
		var where = document.getElementById('ar-steps');
		where.textContent = '';
		if (!results.length) return;

		var changed = 0;
		results.forEach(function (result) {
			if (result.changed) changed++;
			result.steps.forEach(function (step) {
				var text = result.name + ': ' + step.what
					+ (step.place ? ' from ' + step.place : '')
					+ (step.amount ? ' ' + step.amount : '')
					+ (step.detail ? ' — ' + step.detail : '');
				where.appendChild(el('div', 'ar-step' + (step.ok ? '' : ' bad'), text));
			});
		});
		say(changed
			? 'Changed ' + changed + ' of ' + results.length + '.'
			: 'Nothing needed doing.', 'done');
	}

	function restock(id, button) {
		button.disabled = true;
		say('Restocking…', 'busy');
		var params = { restock: 1 };
		if (id) params.item = id;
		ask('/ar_stock.ash', params, function (answer) {
			button.disabled = false;
			state.items = answer.items;
			state.settings = answer.settings;
			drawSettings();
			drawStock();
			drawSteps(answer.results);
		});
	}

	function loadStock(quiet) {
		if (!quiet) say('Reading your store…', 'busy');
		ask('/ar_items.ash', {}, function (answer) {
			state.items = answer.items;
			state.settings = answer.settings;
			if (!quiet) say('');
			drawSettings();
			drawStock();
			drawChosen();
		});
	}

	// --- Sales ------------------------------------------------------------

	function fillFilter(select, values, chosen, anything) {
		select.textContent = '';
		var any = el('option', null, anything);
		any.value = '';
		select.appendChild(any);
		values.slice().sort(function (a, b) {
			return a.toLowerCase().localeCompare(b.toLowerCase());
		}).forEach(function (value) {
			var option = el('option', null, value);
			option.value = value;
			if (value === chosen) option.selected = true;
			select.appendChild(option);
		});
	}

	// What each column sorts on. "When" is built into a string that sorts
	// right -- KoL writes MM/DD/YY, which puts March 2026 before April 2025 --
	// rather than trusting the order the log happened to arrive in, since that
	// is KoLmafia's Store Manager sort setting and not ours to rely on.
	var SORT_KEYS = {
		when: function (s) {
			var d = String(s.date || '').split('/');
			return d.length === 3
				? d[2] + '-' + d[0] + '-' + d[1] + ' ' + (s.time || '')
				: String(s.stamp || '');
		},
		buyer: function (s) { return String(s.buyer || '').toLowerCase(); },
		qty:   function (s) { return Number(s.qty) || 0; },
		item:  function (s) { return String(s.name || '').toLowerCase(); },
		meat:  function (s) { return Number(s.meat) || 0; }
	};

	function sortSales(key) {
		// The same column again turns it round; a different one starts it the
		// way that column reads best -- newest and biggest first, names from A.
		if (state.sortBy === key) {
			state.sortDesc = !state.sortDesc;
		} else {
			state.sortBy = key;
			state.sortDesc = (key === 'when' || key === 'qty' || key === 'meat');
		}
		drawSales();
	}

	function drawSales() {
		var where = document.getElementById('ar-sales');
		where.textContent = '';

		var shown = state.sales.filter(function (sale) {
			if (state.filterItem && sale.name !== state.filterItem) return false;
			if (state.filterBuyer && sale.buyer !== state.filterBuyer) return false;
			return true;
		});

		var keyOf = SORT_KEYS[state.sortBy] || SORT_KEYS.when;
		shown.sort(function (a, b) {
			var x = keyOf(a), y = keyOf(b);
			// A tie keeps the log's own order, so four sales in the same second
			// do not shuffle between redraws.
			if (x === y) return (a.id || 0) - (b.id || 0);
			return (x < y ? -1 : 1) * (state.sortDesc ? -1 : 1);
		});

		if (!shown.length) {
			where.appendChild(el('p', 'ar-dim',
				state.sales.length ? 'Nothing matches those filters.'
					: 'No ticket of yours has sold.'));
			return;
		}

		var t = table([
			{ text: 'When', key: 'when' },
			{ text: 'Buyer', key: 'buyer' },
			{ text: 'Qty', num: true, key: 'qty' },
			{ text: 'Item', key: 'item' },
			{ text: 'Meat', num: true, key: 'meat' }
		], { by: state.sortBy, desc: state.sortDesc }, sortSales);

		shown.forEach(function (sale) {
			var tr = el('tr');
			cell(tr, sale.stamp);
			cell(tr, sale.buyer);
			cell(tr, sale.qty, 'num');

			var name = el('td');
			if (sale.image) {
				name.appendChild(icon(sale.image));
				name.appendChild(document.createTextNode(' '));
			}
			name.appendChild(document.createTextNode(sale.name));
			tr.appendChild(name);

			cell(tr, meat(sale.meat), 'num');
			t.appendChild(tr);
		});

		where.appendChild(t);
	}

	function loadSales() {
		say('Reading the sales log…', 'busy');
		ask('/ar_sales.ash', {}, function (answer) {
			state.sales = answer.sales;
			state.buyers = answer.buyers;
			state.names = answer.names;
			fillFilter(document.getElementById('ar-by-item'), answer.names,
				state.filterItem, 'Every item');
			fillFilter(document.getElementById('ar-by-buyer'), answer.buyers,
				state.filterBuyer, 'Every buyer');
			say(answer.unreadable
				? answer.unreadable + ' line(s) of the store log could not be read, '
					+ 'and one of them could be a ticket sale.'
				: '');
			drawSales();
		});
	}

	// --- Tabs -------------------------------------------------------------

	function show(which) {
		var tabs = document.querySelectorAll('.ar-tab');
		for (var i = 0; i < tabs.length; i++) {
			tabs[i].className = 'ar-tab' + (tabs[i].getAttribute('data-tab') === which ? ' on' : '');
		}
		var panels = document.querySelectorAll('.ar-panel');
		for (var j = 0; j < panels.length; j++) {
			panels[j].className = 'ar-panel'
				+ (panels[j].id === 'ar-panel-' + which ? ' on' : '');
		}

		// Each tab asks for its own data the first time it is opened, and
		// reading the store is a request to KoL -- so opening the page does not
		// fetch a sales log nobody asked to see.
		if (which === 'sales' && !state.loaded.sales) {
			state.loaded.sales = true;
			loadSales();
		}
		if ((which === 'stock' || which === 'tickets') && !state.loaded.stock) {
			state.loaded.stock = true;
			loadStock();
		}
	}

	function start() {
		var tabs = document.querySelectorAll('.ar-tab');
		for (var i = 0; i < tabs.length; i++) {
			tabs[i].onclick = function () { show(this.getAttribute('data-tab')); };
		}

		document.getElementById('ar-q').oninput = searchSoon;

		document.getElementById('ar-by-item').onchange = function () {
			state.filterItem = this.value;
			drawSales();
		};
		document.getElementById('ar-by-buyer').onchange = function () {
			state.filterBuyer = this.value;
			drawSales();
		};

		show('tickets');
	}

	if (document.readyState === 'loading') {
		document.addEventListener('DOMContentLoaded', start);
	} else {
		start();
	}
})();
