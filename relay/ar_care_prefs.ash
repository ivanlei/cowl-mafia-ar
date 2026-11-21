// ar_care_prefs.ash -- changes one of the Care Packages page's own settings.
//
//     ?name=<preference>&value=<value>
//
// Only the three the Config box carries a control for (careSettable, in
// ar_care.ash). A relay script answers whatever the browser asks it, and "set
// any preference you like" is not a thing to leave lying in the relay folder,
// so a name that is not one of those is refused rather than set.
//
// THE FIRST THING IN THIS REPOSITORY THAT WRITES ON THIS PAGE'S BEHALF. Care
// Packages was read-only until 2026-11-21 -- its settings were typed into the
// gCLI, and its own header said so. What changed is COwliCK asking for the
// Config box: "Active Means: Logged in within <text entry> days", checkboxes
// for the places, a text entry for the note. The scan endpoint beside this one
// writes too, but only this page's own cache; this writes KoLmafia preferences.
//
// It still sends nothing and still cannot: there is no send endpoint in this
// repository at all.
//
// ar_prefs.ash is the same thing for the anti-raffle page and this is modelled
// on it deliberately -- same four-line shape, same allowlist-then-validate
// order, same answer. The one difference is where the rules live: arBadValue()
// is in that endpoint, careBadValue() is in ar_care.ash, so that
// care_packages.test.ash can check the rules without a running relay.

import <ar_care.ash>
import <ar_relay.ash>

// The settings AS THEY NOW STAND, rather than as they were asked to be: a
// value KoLmafia normalised on the way in should be the one the page goes on
// showing. ar_prefs.ash answers the same way and for the same reason.
//
// The places come back as the full list with a flag each, not as the enabled
// ones, because the page draws a checkbox per place and needs to know about
// the ones that are off.
string carePartJson(care_part p) {
	buffer out;
	out.append("{\"qty\":" + p.qty);
	// The NAME, not whatever was stored. A part can be held as KoLmafia's
	// bracketed id (carePackageTerm, for an item with a comma in its name),
	// and "[8254]" is not what a box the width of the page should show.
	out.append(",\"name\":" + arQuoted(p.what == $item[none]
		? p.named : p.what.to_string()) + "}");
	return out.to_string();
}

string careSettingsJson() {
	buffer out;
	out.append("{\"days\":" + careDays());
	out.append(",\"note\":" + arQuoted(careNote()));
	out.append(",\"meat\":" + careMeat());
	out.append(",\"package\":[");
	foreach i, p in carePackageParts(carePackage()) {
		if (i > 0) out.append(",");
		out.append(carePartJson(p));
	}
	out.append("]");
	out.append(",\"sources\":[");
	boolean [string] on = careSources();
	foreach i, place in careAllSources() {
		if (i > 0) out.append(",");
		out.append("{\"place\":" + arQuoted(place));
		out.append(",\"enabled\":" + (on contains place ? "true" : "false") + "}");
	}
	out.append("]}");
	return out.to_string();
}

void main() {
	if (!arAuthorised()) {
		arRefuseStale();
		return;
	}

	string name = form_field("name");
	string value = form_field("value");

	// ALLOWLIST FIRST, THEN THE VALUE. careBadValue() answers "Not a setting
	// this touches." for an unknown name too, so this check is not the only
	// thing standing between the browser and set_property -- but it is the one
	// that is obviously doing it, and a reader should not have to follow a
	// validator's last line to find the gate.
	if (!(careSettable() contains name)) {
		arRefuse("Not a setting this touches.");
		return;
	}

	// THE PACKAGE ARRIVES ONE ENTRY PER LINE AND IS STORED COMMA-SEPARATED,
	// and the conversion happens BEFORE the value is validated, so that what
	// is checked is exactly what will be written.
	//
	// Two formats because the stored one is KoLmafia's and cannot carry an
	// item with a comma in its name. carePartsFromLines() reads what the box
	// sent; carePackageList() writes the form that reads back, putting the
	// awkward names in as [id]. The page sends plain names and never has to
	// know any of this. See carePartsFromLines() in ar_care.ash.
	string stored = name == CARE_PACKAGE
		? carePackageList(carePartsFromLines(value)) : value;

	string wrong = careBadValue(name, stored);
	if (wrong != "") {
		arRefuse(wrong);
		return;
	}

	set_property(name, stored);

	write("{\"ok\":true,\"error\":\"\",\"settings\":" + careSettingsJson() + "}");
}
