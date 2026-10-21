// ar_assets.ash -- the address to load this repository's stylesheet or script
// from, so that a browser fetches it again after an update.
//
// KoLmafia serves a user relay file with a Last-Modified and no Expires, so it
// revalidates and an edit is picked up at once. The version still earns its
// place: a new version is a new address the browser has never cached, which
// right after an update -- when every file may have changed -- is exactly what
// you want, and it is what stops an iPad going on running the script it had
// before the fix.
//
// The commit and the file's own length, both. The commit changes with every
// `git update`, which is what a normal install needs; the length changes with
// most edits, which is what trying a change out needs, since a file copied
// into the relay folder by hand sits under a commit that has not moved.

string AR_GIT_PROJECT = "ivanlei-cowl-mafia-ar";

string arAssetVersion(string file) {
	string commit = git_info(AR_GIT_PROJECT).commit;
	string at = commit.length() > 12 ? commit.substring(0, 12) : commit;
	return (at == "" ? "n" : at + "-") + file_to_buffer(file).length();
}

string arAsset(string file) {
	return "/" + file + "?v=" + arAssetVersion(file);
}

// In <head>, where the rules are in hand before the first row is parsed.
// Appending a stylesheet after the page is the obvious thing and the wrong
// one: the browser has painted the table by the time it reaches the link, and
// everything snaps into place a moment later.
string arStyle(string file) {
	return "<link rel='stylesheet' type='text/css' href='" + arAsset(file) + "'>\n";
}

string arScript(string file) {
	return "<script type='text/javascript' src='" + arAsset(file) + "'></script>\n";
}
