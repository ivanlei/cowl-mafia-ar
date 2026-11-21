// ar_box.ash -- KoL's own section box, for a page of ours to draw one.
//
// KoL divides every page into sections the same way, everywhere: a bar with
// the section's name centred on it in white, and the section's contents under
// it inside a thin border of the same colour. "Results:", "2002 Mr. Store",
// the clan hall's every panel -- all the same box. A page of ours that invents
// its own heading does not look like the game it is part of, which is what
// this is here to stop.
//
// A FUNCTION RATHER THAN A CLASS NAME, because this is three opening tags and
// two closing ones in the right order. That is enough to get subtly wrong in
// each page separately, and a <details> left unclosed swallows everything
// after it into the fold.
//
// THE PAGE LINKS ar_box.css ITSELF. Every page here writes its own <head> and
// links what it uses (see relay_Care_Packages.ash), so there is nowhere in a
// markup helper to put a stylesheet link that would not be a surprise.
//
// COLLAPSING IS THE <details> ELEMENT'S OWN, so it needs no script and keeps
// working with scripting off. The widget does not remember what you left
// folded: reopening the page opens every section again. That is deliberate --
// remembering it means somewhere to put it, and where is a decision the page
// is better placed to make than this is.

// Opens a section. `open` is whether it starts unfolded. This is the one that
// builds the tag and the short form hands down to it -- IN THAT ORDER, because
// ASH resolves a call against what it has already read, and a function defined
// after its caller is simply undefined.
//
// THE TITLE IS IN TITLE CASE, by the rules a book title uses: every important
// word capitalised and the small joining ones -- a, an, the, and, but, or, of,
// in, on, to, by -- left lower unless they begin or end it. So "Clan Members",
// "Config", "Last Login". COwliCK asked for this as the rule for section
// headers, so it is written here rather than on the one page that prompted it:
// this is where the next section header in this repository gets written.
//
// THE BAR CARRIES A NAME AND NOTHING ELSE. No count, no subtext, no second
// line -- KoL never puts one there, and a widget whose whole purpose is to look
// like the game should not invent one in the single place the resemblance
// matters most. A folded section shows its name and nothing else, which is the
// element's own behaviour and the game's own look.
//
// Otherwise the title is written in as given, so a caller that wants markup in
// it can have it -- and a caller passing a name with an ampersand or a bracket
// in it must encode it first, the same contract KoL's own bars keep.
string arBoxStart(string title, boolean open) {
	return "<details class=\"ar-box\"" + (open ? " open" : "") + ">"
		+ "<summary>" + title + "</summary>"
		+ "<div class=\"ar-box-body\">";
}

// Open unless you say otherwise: a section folded on arrival is one whose
// contents nobody knows are there.
string arBoxStart(string title) {
	return arBoxStart(title, true);
}

string arBoxEnd() {
	return "</div></details>";
}
