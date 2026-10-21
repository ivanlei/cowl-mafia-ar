// ar_prefs.ash -- changes one of this script's own settings.
//
//     ?name=<preference>&value=<value>
//
// Only the five below. A relay script answers whatever the browser asks it,
// and "set any preference you like" is not a thing to leave lying in the relay
// folder, so a name that is not one of these is refused rather than set.
//
// arPriceLevel and arMaxPrice are deliberately settable to the empty string:
// unset is not zero. Unset means "whatever the maximizer's field says", zero
// means the field was emptied, and the two fall through differently --
// arLimitsNow() in ar_core.ash has the chain.

import <ar_relay.ash>

boolean [string] arSettable() {
	boolean [string] allowed;
	allowed[AR_COUNT] = true;
	allowed[AR_PARK] = true;
	allowed[AR_SOURCES] = true;
	allowed[AR_PRICE_LEVEL] = true;
	allowed[AR_MAX_PRICE] = true;
	return allowed;
}

// Each setting's own rule. A refusal says what was wrong with the value and
// never repeats the value back.
string arBadValue(string name, string value) {
	if (name == AR_SOURCES) {
		if (value == "") return "Name at least one source.";
		string [int] pieces = value.split_string(",");
		foreach i, place in pieces {
			if (!arIsSource(place)) return "Not a source this knows.";
		}
		return "";
	}

	// The other four are numbers, and two of them may also be empty.
	if (value == "") {
		if (name == AR_PRICE_LEVEL || name == AR_MAX_PRICE) return "";
		return "Not a number.";
	}
	if (!value.is_integer()) return "Not a number.";

	int n = value.to_int();
	if (name == AR_COUNT && n < 1) return "Hold at least one.";
	if (name == AR_PARK && (n < 1 || n > AR_MALL_MAX)) {
		return "Outside what KoL allows for a price.";
	}
	if (n < 0) return "Not a number.";
	return "";
}

void main() {
	if (!arAuthorised()) {
		arRefuseStale();
		return;
	}

	string name = form_field("name");
	string value = form_field("value");

	if (!(arSettable() contains name)) {
		arRefuse("Not a setting this touches.");
		return;
	}

	string wrong = arBadValue(name, value);
	if (wrong != "") {
		arRefuse(wrong);
		return;
	}

	set_property(name, value);

	// The settings come back as they now stand, rather than as they were
	// asked to be: a value KoLmafia normalised on the way in should be the one
	// the page goes on showing.
	write("{\"ok\":true,\"error\":\"\",\"settings\":" + arSettingsJson() + "}");
}
