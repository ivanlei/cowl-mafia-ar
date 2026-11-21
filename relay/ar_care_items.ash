// ar_care_items.ash -- what the Package box suggests.
//
//     ?have=1    every giftable item the allowed places hold, with a count
//
// WHY WHAT YOU HOLD, rather than every item in the game. The same reasoning
// ar_items.ash gives for the anti-raffle's dropdown: a list of thirty
// thousand items, nearly all of which you own none of, is a list you have to
// know the answer before you can use. KoL's own kmail form offers your
// inventory and nothing else, and this box is meant to look like it.
//
// BUT THE LIST ONLY SUGGESTS. The page puts these in ar_combo.js, which
// narrows as you type and does not constrain what you may type -- so an item
// you mean to buy before you send is still nameable, and ar_care_prefs.ash
// validates it against the real item database either way. That matters here
// in a way it does not for the anti-raffle: a package for a couple of hundred
// people is something you go and buy, not something already in your closet.
//
// WHAT CANNOT BE SENT IS LISTED TOO, AND SAID SO. is_giftable() is what ASH
// knows about sending, and a bound item cannot leave however it is packed --
// so for a while this left them out, on the reasoning that offering one would
// be offering a refusal.
//
// That was the wrong end of it. 262 of the 879 things in COwliCK's display
// case cannot be gifted (the Epic weapons, the old untradeable trophies, every
// quest item) and 279 of the 1563 in his inventory, so typing the name of
// something he owns and being told "Nothing you hold matches" was the common
// case rather than the odd one -- and the display case, where the proportion
// is worst, is where he noticed it: "the combo to select items to send doesn't
// seem to like what's in closet or DC" (2026-11-21).
//
// The sentence was also simply false. He does hold it. So every held item is
// listed with a `gift` flag, the page draws the unsendable ones greyed and
// says why, and the only thing it will not do is let one be picked.
//
// THE ALLOWED PLACES, not all four. careSources() is the Config box's "Gather
// Items From", and Hagnk's is not among them at all any more (COwliCK,
// 2026-11-21). Suggesting something only reachable from a place you have
// turned off is suggesting a package that cannot be packed.

import <ar_care.ash>
import <ar_relay.ash>

// Counted across the allowed places, since the same item in the closet and in
// the display case is one entry in a dropdown and not two. careReachable()
// does the counting and the limit handling -- a display case is shut in Ronin
// -- so this is only the walk.
//
// Read fresh on every call, like arHeld(): get_inventory(), get_closet() and
// get_display() each walk KoLmafia's live list, so the suggestions are
// whatever KoLmafia believes you hold at the moment the page opened.
void careHeld() {
	boolean [item] seen;
	arLimits limits = arLimitsNow();
	boolean [string] on = careSources();

	void gather(int [item] held) {
		foreach it, n in held {
			if (n < 1) continue;
			seen[it] = true;
		}
	}

	if (on contains "inventory") gather(get_inventory());
	if (on contains "closet")    gather(get_closet());
	if (on contains "display")   gather(get_display());

	buffer out;
	out.append("{\"ok\":true,\"error\":\"\",\"held\":[");
	boolean first = true;
	foreach it in seen {
		// STILL FILTERED ON REACH, for both kinds. Nought reachable means the
		// allowed places hold none of it today -- a display case is shut in
		// Ronin -- which is a different statement from "it cannot be gifted"
		// and not one the page has anything useful to say about.
		int reach = careReachable(it, limits);
		if (reach < 1) continue;

		if (!first) out.append(",");
		first = false;
		out.append("{\"name\":" + arQuoted(it.to_string()));
		out.append(",\"have\":" + reach);
		out.append(",\"gift\":" + (it.is_giftable() ? "true" : "false") + "}");
	}
	out.append("]}");
	out.write();
}

void main() {
	if (!arAuthorised()) {
		arRefuseStale();
		return;
	}

	if (form_field("have") != "") {
		careHeld();
		return;
	}

	arRefuse("Ask for ?have=1.");
}
