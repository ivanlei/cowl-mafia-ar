// relay_Anti_Raffle.ash -- the page, which KoLmafia lists in the relay
// browser's Scripts menu because of the relay_ prefix on its name.
//
// A document and nothing else: three empty tabs, the password hash, and the
// two files that fill them. Everything the page shows comes from the four
// endpoints beside it, which are the same functions the `ar` gCLI command
// uses -- so the page and the command cannot disagree about what is in your
// store.
//
// No framework and no CDN. The stylesheet and the script are this
// repository's own files, served by KoLmafia from the relay folder with a
// version in the address (ar_assets.ash) so that an iPad picks up an edit.

import <ar_assets.ash>

void main() {
	buffer out;

	out.append("<!DOCTYPE html>\n<html><head>\n");
	out.append("<title>Anti-Raffle</title>\n");
	out.append("<meta name='viewport' content='width=device-width, initial-scale=1'>\n");
	out.append(arStyle("ar_relay.css"));
	// The hash every endpoint checks. It is in every relay page KoL and
	// KoLmafia serve, for the same reason: without it a page cannot ask
	// KoLmafia for anything.
	out.append("<script type='text/javascript'>var arPwd = \"" + my_hash() + "\";</script>\n");
	out.append("</head>\n<body>\n");

	out.append("<div id='ar'>\n");

	out.append("<div id='ar-tabs'>");
	out.append("<button class='ar-tab' data-tab='tickets'>Tickets</button>");
	out.append("<button class='ar-tab' data-tab='stock'>Stock</button>");
	out.append("<button class='ar-tab' data-tab='sales'>Sales</button>");
	out.append("</div>\n");

	out.append("<div id='ar-note'></div>\n");

	out.append("<div class='ar-panel' id='ar-panel-tickets'>\n");
	// The shipped list first, because it is the thing to press when the list
	// is empty and there is nothing else on the tab to do.
	out.append("<div class='ar-row'>");
	out.append("<button class='ar-go' id='ar-defaults'>Use default item list</button>");
	out.append("</div>\n");

	// A box and a list at once: <datalist> is the native combo, so you can type
	// a name and have it narrow as you go, or open the list and pick one. It
	// holds what you hold and could put in the mall, which is the list worth
	// having -- the box this replaced searched the whole game and answered
	// with a table that looked exactly like the ticket list under it.
	out.append("<div class='ar-row'>");
	out.append("<input type='text' id='ar-held' list='ar-held-list'"
		+ " autocomplete='off' spellcheck='false'"
		+ " placeholder='Type or pick an item you hold'>");
	out.append("<datalist id='ar-held-list'></datalist>");
	out.append("<button class='ar-go' id='ar-add'>Add</button>");
	out.append("</div>\n");
	out.append("<div id='ar-chosen'></div>\n");
	out.append("</div>\n");

	out.append("<div class='ar-panel' id='ar-panel-stock'>\n");
	out.append("<div id='ar-settings'></div>\n");
	out.append("<div id='ar-stock'></div>\n");
	out.append("<div id='ar-steps'></div>\n");
	out.append("</div>\n");

	out.append("<div class='ar-panel' id='ar-panel-sales'>\n");
	// No "everything" switch: the sales tab is the ticket sales, because that
	// is the list a winner gets read out of.
	out.append("<div class='ar-row'>");
	out.append("<select id='ar-by-item'></select>");
	out.append("<select id='ar-by-buyer'></select>");
	// The filters work on what is already here; this is how you go and ask KoL
	// again, which is the one thing on this page worth asking twice.
	out.append("<button class='ar-go' id='ar-refresh'>Refresh data</button>");
	out.append("</div>\n");
	out.append("<div id='ar-sales'></div>\n");
	out.append("</div>\n");

	out.append("</div>\n");

	out.append(arScript("ar_relay.js"));
	out.append("</body></html>\n");

	out.write();
}
