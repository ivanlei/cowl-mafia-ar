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
	out.append("<div class='ar-search'>");
	out.append("<input type='text' id='ar-q' autocomplete='off' spellcheck='false'"
		+ " placeholder='Find an item to use as a ticket'>");
	out.append("</div>\n");
	out.append("<div id='ar-found'></div>\n");
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
	out.append("<div class='ar-filters'>");
	out.append("<select id='ar-by-item'></select>");
	out.append("<select id='ar-by-buyer'></select>");
	out.append("</div>\n");
	out.append("<div id='ar-sales'></div>\n");
	out.append("</div>\n");

	out.append("</div>\n");

	out.append(arScript("ar_relay.js"));
	out.append("</body></html>\n");

	out.write();
}
