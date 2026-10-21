#!/usr/bin/env python3
"""What to run before pushing a change: python3 .github/check.py

Nothing here builds anything - the repository ships what it is, ASH and plain
relay JS - so these are the three ways a change can break the installed copy
without the file it broke looking wrong on its own.

Lives in .github/ rather than scripts/ on purpose: KoLmafia installs
scripts/, relay/, data/, images/, ccs/ and planting/ (ScriptManager.java), so a
checker in any of those would be copied into whoever's mafia folder.
"""

import re
import subprocess
import sys
from pathlib import Path

# Imports expected to come from another installed project rather than from
# this one. Empty, and meant to stay empty: this repository is self-contained,
# and an import that resolved somewhere else would make it depend on whatever
# else the person happens to have installed.
EXTERNAL_IMPORTS = set()

# Where KoLmafia resolves an `import <x.ash>` from, among the folders we ship.
IMPORT_DIRS = ("relay", "scripts")


def tracked():
    # Files that are not committed yet count too. CI only ever sees a commit, so
    # there the two are the same; run by hand before `git add`, the difference is
    # every new file looking like a missing one - which is how this first
    # reported a stylesheet that was sitting right there.
    out = subprocess.run(
        ["git", "ls-files", "--cached", "--others", "--exclude-standard"],
        capture_output=True, text=True, check=True
    ).stdout
    return sorted(p for p in out.split("\n") if p)


def read(path):
    return Path(path).read_text(errors="replace")


def check_js_syntax(files, fail):
    # A relay page that loads a script with a syntax error renders without it and
    # says nothing, so this is the only place a typo there gets caught.
    for f in files:
        if not f.endswith(".js"):
            continue
        r = subprocess.run(["node", "--check", f], capture_output=True, text=True)
        if r.returncode != 0:
            fail(f, r.stderr.strip().split("\n")[0])


def check_assets(files, fail, shipped):
    # arAsset("x") serves /x, and arAssetVersion reads it to stamp the
    # address, so a name that doesn't ship is a 404 and an empty version.
    for f in files:
        if not f.endswith((".ash", ".js")):
            continue
        for m in re.finditer(r'arAsset\("([^"]+)"\)', read(f)):
            asset = m.group(1)
            if f"relay/{asset}" not in shipped:
                fail(f, f'arAsset("{asset}") has no relay/{asset}')


def check_imports(files, fail, shipped):
    # An unresolved import aborts the script at load, in a page that otherwise
    # looks fine.
    for f in files:
        if not f.endswith((".ash", ".js")):
            continue
        for m in re.finditer(r"import\s+<([^>]+)>", read(f)):
            name = m.group(1)
            if name in EXTERNAL_IMPORTS:
                continue
            if not any(f"{d}/{name}" in shipped for d in IMPORT_DIRS):
                fail(f, f"import <{name}> is not in {' or '.join(IMPORT_DIRS)}/")



# ASH's own library is large and we do not have a list of it, so this does not
# try to know what is built in. It knows what THIS repository defines, which is
# enough for the mistake it exists to catch: a function that was here, is called
# from another file, and is not here any more.
# Two sets, and they are not interchangeable. STATEMENTS is what a line can
# start with that makes it not a definition -- `return get_property(` and
# `for i from first to count(` are calls. TYPES is what a definition's first
# token looks like, and those must NOT be used to reject a line: `string
# cowlModBox(` starts with a type, and rejecting it is how the first version of
# this found 2 definitions in cowl_mods.ash instead of 39 and then reported
# that everything resolved.
STATEMENTS = {
    "if", "while", "foreach", "for", "switch", "case", "return", "repeat",
    "until", "else", "elseif", "try", "finally", "catch", "do", "in", "by",
    "remove", "new", "exit", "break", "continue", "sort", "default", "typedef",
    "static", "and", "or", "not", "delete", "print",
}

# Not called, so never mistaken for a function someone forgot to import.
TYPES = {
    "void", "boolean", "int", "float", "string", "buffer", "matcher", "item",
    "effect", "skill", "familiar", "location", "monster", "slot", "element",
    "class", "stat", "phylum", "coinmaster", "thrall", "servant", "vykea",
    "path", "bounty", "modifier", "record", "aggregate",
}

# A definition is one type token -- optionally with ASH's aggregate brackets, as
# in `familiar [item] cowlFamOwners()` -- then the name, then the paren. One
# token and not more, or `return get_property(` and `for i from first to count(`
# read as definitions of get_property and count, which is how the first version
# of this decided ASH's own library belonged to us.
DEF = re.compile(
    r"^\s*([A-Za-z_][A-Za-z0-9_]*)(?:\s*\[[^\]]*\])?\s+([a-zA-Z_][a-zA-Z0-9_]*)\s*\(",
    re.M,
)
CALL = re.compile(r"(?<![A-Za-z0-9_$.])(?<!new )([a-zA-Z_][a-zA-Z0-9_]*)\s*\(")
RECORD = re.compile(r"^\s*record\s+([a-zA-Z_][a-zA-Z0-9_]*)", re.M)
IMPORT = re.compile(r"import\s+<([^>]+)>")


def ash_strip(text):
    # Comments and double-quoted strings, so a function name written inside
    # either is not read as code. ASH has no block comment.
    #
    # Apostrophes are left alone. Treating them as string delimiters the way the
    # first version did was quietly catastrophic: an apostrophe in one place
    # pairs with the next one anywhere in the file and everything between them
    # disappears, which took cowl_mods.ash from 49 visible definitions to 2 and
    # made the whole check pass by having almost nothing to check.
    text = re.sub(r"//[^\n]*", "", text)
    return re.sub(r'"(?:[^"\\\n]|\\.)*"', '""', text)


def ash_defines(text):
    # Lowercased: ASH identifiers are case-insensitive, so a call to cowlPlain
    # and a definition of cowlplain are the same function.
    found = set()
    for m in DEF.finditer(text):
        if m.group(1).lower() in STATEMENTS:
            continue
        found.add(m.group(2).lower())
    # A record is a type, and `new arNotice(...)` reads as a call to it. ASH
    # identifiers are case-insensitive, so a record here and a function of the
    # same name elsewhere are one name to this check; counting the record as
    # defined is what keeps them apart.
    found |= {m.group(1).lower() for m in RECORD.finditer(text)}
    return found - STATEMENTS - TYPES


def check_ash_symbols(files, fail, shipped):
    # A relay script that will not compile is served as a one-byte 404 -- no
    # error, no stack trace, just a page that stopped. That is what happened to
    # the Beret Busking and Leprecondo pages when a block was cut by its
    # boundary comments and took three shared functions with it (#186, #187).
    # check_imports would not have caught it: every import still resolved, and
    # the functions those imports used to provide were simply gone.
    ash = sorted(f for f in files if f.endswith(".ash"))
    text = {f: ash_strip(read(f)) for f in ash}
    defines = {f: ash_defines(text[f]) for f in ash}

    # Whose function is this?
    #
    # Being defined somewhere in the repository is not the test, and getting
    # that wrong is the whole reason this check exists: when #186 deleted
    # cowlEffectBoxes it was no longer defined ANYWHERE, so a "do we define it?"
    # rule concluded it must be ASH's and said nothing. The deletion is the case
    # to catch, so it cannot be the case that disables the catching.
    #
    # The discriminator is the name. ASH's own library is uniformly
    # lower_snake_case -- create_matcher, item_amount, visit_url -- and nothing
    # this repository defines uses an underscore (checked: 0 of 36). So a
    # capital letter means ours, whether or not a definition still exists.
    ours = set()
    for names in defines.values():
        ours |= names

    def is_ours(raw_name):
        return raw_name != raw_name.lower() or raw_name.lower() in ours

    by_name = {}
    for f in ash:
        for d in defines[f]:
            by_name.setdefault(d, set()).add(f)

    def reachable(start):
        # start, plus everything it imports, transitively.
        seen, queue = {start}, [start]
        while queue:
            f = queue.pop()
            for m in IMPORT.finditer(text.get(f, "")):
                for d in IMPORT_DIRS:
                    cand = f"{d}/{m.group(1)}"
                    if cand in shipped and cand not in seen:
                        seen.add(cand)
                        queue.append(cand)
        return seen

    for f in ash:
        here = reachable(f)
        have = set()
        for g in here:
            have |= defines.get(g, set())
        called = {}
        for m in CALL.finditer(text[f]):
            called.setdefault(m.group(1).lower(), m.group(1))
        for name in sorted(called):
            if name in STATEMENTS or name in TYPES or name in have:
                continue
            if not is_ours(called[name]):
                continue
            where = by_name.get(name)
            detail = (
                f"defined only in {', '.join(sorted(where))} -- not imported here"
                if where
                else "is not defined anywhere in this repository"
            )
            fail(f, f"calls {called[name]}(), which {detail}")


def check_tests(files, fail):
    # A test under tests/ is one somebody wrote because the thing it covers is
    # not obvious by reading it. Running them here means a change that breaks
    # one is caught before it is pushed rather than by missing an auction.
    for f in sorted(files):
        if not f.startswith("tests/") or not f.endswith(".test.js"):
            continue
        done = subprocess.run(
            ["node", f], capture_output=True, text=True
        )
        if done.returncode != 0:
            detail = (done.stderr or done.stdout).strip().splitlines()
            fail(f, "; ".join(detail[-4:]) or "failed")


def main():
    files = tracked()
    shipped = set(files)
    problems = []

    def fail(where, what):
        problems.append(f"{where}: {what}")

    check_js_syntax(files, fail)
    check_assets(files, fail, shipped)
    check_imports(files, fail, shipped)
    check_ash_symbols(files, fail, shipped)
    check_tests(files, fail)

    if problems:
        print(f"{len(problems)} problem(s):", file=sys.stderr)
        for p in problems:
            print(f"  {p}", file=sys.stderr)
        return 1

    js = sum(1 for f in files if f.endswith(".js"))
    ash = sum(1 for f in files if f.endswith(".ash"))
    print(f"ok: {js} js files parse; assets, imports and ash symbols resolve across {ash} ash files")
    return 0


if __name__ == "__main__":
    sys.exit(main())
