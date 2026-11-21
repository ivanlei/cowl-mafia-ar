# cowl-mafia-ar

Hosting anti-raffles in the Kingdom of Loathing, from KoLmafia: a relay page
and a gCLI command that keep the tickets stocked and tell you what sold.

An [anti-raffle](https://wiki.kingdomofloathing.com/Antiraffle) is a game you
host. You put a number of a good item in your store at or near its minimum
price with a per-person limit, announce it in `/games`, and when the tickets
have sold you have a bot roll `1d<tickets>` and read the winning line out of
your store's sales log. Whoever loses still bought something under mall price,
which is the point of it.

This does the bookkeeping either side of that: which items you use as tickets,
getting them into the store and parked, and reading back what sold.

There is a second page here now — **Care Packages**, further down — which uses
the same item sourcing. Both are about taking things you hold and getting them
to other people, so they ask "where may this come from, and will that place
hand it over today" the same way rather than each keeping an answer.

## What it does

**Tickets.** Choose the items you use as tickets. Type a name or pick one from
the list — it is a `<datalist>`, so the box is both — and it holds everything
tradeable in your inventory, closet, display case and Hagnk's. Read fresh
every time the tab opens, so it is whatever you hold now. Return adds, as does
the button. The gCLI's `ar add` takes any item by name or id, held or not. They are kept as item ids, so a
rename or a comma in a name cannot break the list.

**Default items** on that tab, or `ar defaultitems`, fills the list with **79
items** that make reasonable tickets — all tradeable, all worth more than the
minimum price they can be sold at, spread across food, drink, one-day passes,
the pastes and a few oddities. Then cut it down to the handful you actually
keep in stock.

It is a button and not a default, which is the whole point: your tickets are
whatever you last said they were. A list that refills itself when you empty it
cannot be emptied.

**Stock.** How many of each to stock and what to park them at, which sources
restocking may draw from, and for each ticket: how many are listed, at what price and limit, how
many each place you keep things could supply, and how far short of your target
you are. **Restock** gathers the shortfall, lists it one-per-person, and parks it at
a price nobody can pay — so that announcing a raffle later is one price change rather
than a scramble to list a dozen items while `/games` waits.

**Nothing here buys anything.** Every source moves something you already own
from one place you own to another, so hosting a raffle costs tickets and no
meat. The mall price is shown against each ticket, because an item worth more
than it sells for is the whole definition of one — but it is read, never used
to spend.

**Sales.** Sales of your tickets, newest first, filtered by item or by buyer
and sortable by any column. **Refresh data** asks KoL for the log again,
keeping whatever you had it narrowed to.
Only your tickets: this is the log you read the winner out of, and the rest of
your store is an ordinary sale. If a line of KoL's log cannot be read, the page
says how many rather than quietly leaving them out.

It does **not** announce, roll, pick the winner or send the prize. That half is
still yours.

## Using it

In the relay browser, **Scripts → Anti Raffle**. Or from the gCLI:

```
ar, ar help            the commands below
ar items               the chosen tickets
ar add <item>          choose one
ar remove <item>       unchoose one
ar stock               the store, source by source
ar restock [item]      list and park -- the one command that writes
ar defaultitems        replace the list with the one this ships with
ar count [n]           how many of each to hold (default 11)
ar sources             where restocking may draw from
ar sources add <place>       switch one on
ar sources remove <place>    switch one off
ar sources <list>            set them all at once
ar sales [filter]      ticket sales, by item or buyer
```

The page and the command answer out of the same functions, so they cannot
disagree about what your store holds.

## Care packages

A clan page: of everybody on the roster, who has logged in lately and has not
already had a care package from you. On a clan of a couple of hundred that is
otherwise an evening's work — three pages of roster, a profile each for the
last login, and your own memory for who you already sent to.

**It reads your sent mail for that last part**, rather than keeping a list of
its own, because a list of its own can disagree with the game. Both sent boxes:
KoL deletes the Outbox after two weeks and says so on the page, while the Saved
box says it is never deleted — so a package is saved as it is sent and is still
remembered in a month. A package is told apart from an ordinary conversation by
a marker line in the message, which is why the page does not count the kmail you
sent somebody last Tuesday.

**Nothing is looked up until you ask for it.** The last login is only on each
member's own profile, so a clan of a couple of hundred is a couple of hundred
requests however it is arranged — about a minute of them. So the page draws
straight away from what it already holds, and the look-up is a button: it walks
the roster, then fetches profiles a few at a time with a pause between, buttons
disabled, with a line saying how far it has got and roughly how long is left.
**Stop** ends it after the current batch and keeps what it found, so the button
then offers to continue from there. (It used to spend eighty profile fetches
inside the page render — eight seconds of blank browser, and then a sentence
asking you to reload for the next eighty.)

**What it finds is held for a week**, the roster and the last logins both, with
the age of it printed next to the conclusions drawn from it. That is a real
trade: a last login read six days ago can call somebody quiet who came back on
Tuesday. Shorten the window if that matters more to you than the requests do.

**Your sent mail is not held.** It is re-read every time the page is drawn, at
two requests, because who has already had one is the answer whose being stale
would cost somebody a second package.

**It sends.** The button at the foot of the Care Package box mails everybody
ticked, a few at a time, with a progress line and a Stop. It will not light
until there is something in the package, a note on it, and at least one
person ticked — and it takes two presses: the first arms it and says what the
second will do, because KoL has no unsend.

Each send is KoLmafia's own `csend`, which tries a plain kmail and falls back
to a gift box when KoL refuses one — which is what happens for a recipient in
Hardcore or Ronin. Who has already had one is read out of your Outbox before
each batch, so a send stopped anywhere resumes without sending anybody a
second package.

**The page is two KoL section boxes** — Care Package and Clan Members — which
fold when you tap the bar. Every control on them saves itself as you change
it; there is no Save button anywhere.

**Package is shaped like KoL's own kmail form**: a two-character quantity, the
item beside it, a bold `+` to add another row, a Send Meat box and the note as
a message box. Clearing a row's item name takes it out again.

The item box lists what matches **underneath itself** rather than off to one
side, which is what a native `<datalist>` does in Safari. It suggests the
giftable items the places you allow actually hold, with how many you have, the
way KoL's own dropdown does — but it only suggests, so you can name something
you mean to buy before you send, and it is checked against the real item
database either way.

The top of the same box is who gets one: how recently counts as active, and
which places a package may be packed from.

**Each clan member has a Send tick.** It starts ticked for everyone who would
get a package. Somebody ruled out by a judgement — not logged in lately, a
profile that would not parse, nobody who has looked yet — starts unticked but can be ticked anyway, with the reason shown beside the
box. Somebody who has already had one, an account KoL has marked inactive, and
you get no box at all: those are not opinions to overrule.

**Pressing "Send" in the table header ticks the whole column**, and pressing
it again clears it. Any box still off means the press fills; only a column
that is already full empties, so the second press always undoes the first.

**A Packages column says what this page has sent them lately** — "2
received", always a count, never blank. It counts the packages in your sent
mail carrying the tool's own marker, in the last two weeks, which is how long
KoL keeps an Outbox anyway. Press a non-zero one and the row unfolds to show
each package's date and what was in it.

A package that went as a gift box — which is what happens for a recipient in
Hardcore or Ronin — reads as the box rather than its contents, because the
box is all your Outbox records of it.

**The summary counts the ticks, not who is eligible.** Untick down to three
and it prices three packages — the Meat, the items and the gift boxes all
follow what is ticked, because that is who a send would go to.

**Somebody mid-ascension shows a last login of "astral".** KoL serves an
astral spirit no profile at all — no account-created date, no last login, just
the name and "Astral Spirit" — so there is nothing to judge them by and the
page does not pretend otherwise. They start unticked with *in Valhalla* as the
reason, and the tick is there if you want to send anyway. The ticks are not
remembered across a reload, and changing the two Config settings that re-decide
the table reloads it, so set those first.

Open it from the relay browser's Scripts menu, as "Care Packages".

| Preference | Default | |
|---|---|---|
| `arCareDays` | `14` | logged in this recently counts as active |
| `arCarePackage` | empty | what is in one, in KoLmafia's item-list syntax |
| `arCareMeat` | `0` | Meat to include as well |
| `arCareSources` | `inventory,closet,display` | where a package may be packed from |
| `arCareNote` | a short default | the message that goes with one |
| `arCareHoldDays` | `7` | how long a look-up's roster and last logins are kept |
| `arCareScanBatch` | `5` | profiles fetched per request during a look-up |
| `arCareScanPause` | `1000` | ms between batches — with the batch, about three a second |

The last two are there so you can be gentler on KoL's server than this ships,
without editing a script; `0` for the pause means as fast as it answers.

**Hagnk's storage is not a place a package can be packed from**, and the page
will refuse it rather than accept it and ignore it. A pull out of storage costs
one of the twenty a day Ronin allows, which is worth more than a present. (The
anti-raffle still restocks from storage: that is a different trade, which is
why the two have had separate source settings all along.)

With `arCarePackage` unset the page offers nothing to press and says so — a
tool that gives your items away to a hundred people should not arrive with an
opinion about which ones.

An item whose name has a comma in it — "Oh, the Humanitini", "Trash, a Memoir"
— is stored as KoLmafia's bracketed id instead, because the preference is a
comma-separated list and the name would otherwise split into two entries that
resolve to nothing. That is still item-list syntax and `set arCarePackage = 3
soda water` still works; it only applies to the awkward names, and the page
shows you the name either way.

Two things it will refuse rather than get wrong. **At most five different
items**, because a recipient in Hardcore or Ronin can only be sent a gift box
and KoLmafia's auto-chosen box holds five — a longer package would work for
part of your clan and not the rest. And **if it cannot read your sent mail it
will not offer to send at all**, because an unread mailbox looks exactly like
"nobody has had one", and that is the one direction this must not fail in.



## Settings

Ordinary KoLmafia preferences. Change them on the page, with `ar count` and
`ar sources`, or with `set`.

| Preference | Default | |
|---|---|---|
| `arTicketItems` | empty | the chosen items, as ids |
| `arRestockCount` | `11` | how many of each to hold |
| `arParkPrice` | `999999999999` | the price restock parks at (KoL's ceiling) |
| `arSources` | `inventory,closet,display,storage` | where restocking may draw from |

Those four are the anti-raffle's, and there is no fifth that buys. The care
packages page has its own six, in its section above — it shares the *code* that
reads a source, deliberately not the setting, since storage is a Ronin pull
each and you might well spend those on one and not the other.


## Install

KoLmafia installs it itself. In the gCLI:

```
git checkout https://github.com/ivanlei/cowl-mafia-ar.git
```

`git update` afterwards, which is also how you get later changes. KoLmafia
installs by folder name — `relay/` and `scripts/` — which is why they sit at
the top rather than under a `src/`.

Nothing else is needed: no other script, no library, no build step.

## Layout

```
scripts/ar_core.ash      tickets, settings, sources, stock, sales -- all reading
scripts/ar_restock.ash   the only file that writes
scripts/ar.ash           the gCLI command
relay/relay_Anti_Raffle.ash   the page
relay/ar_items.ash       search, add, remove, the chosen list
relay/ar_stock.ash       restock
relay/ar_sales.ash       the sales log
relay/ar_prefs.ash       settings, allowlisted
relay/ar_relay.ash       what the endpoints share
relay/ar_assets.ash      versioned addresses for the css and js
relay/ar_relay.css, relay/ar_relay.js
relay/relay_Care_Packages.ash the care packages page
relay/ar_care.ash        roster, last logins, sent mail, who would get one
relay/ar_care.css
```

Two things about the layout are load-bearing rather than taste:

**Every file is `ar`-prefixed.** KoLmafia resolves `import <x.ash>` by
searching the root, `scripts/`, `planting/` and `relay/` and taking the single
match (`KoLmafiaCLI.findScriptFile`). Two files of the same name anywhere in
one KoLmafia installation is not a shadowing, it is a hard *too many matches*
error — and every other script you have installed shares those two folders.

**The core lives in `scripts/` and is imported from `relay/`.** That same
search is what lets one copy of the logic serve both the page and the command.

**Nothing here depends on anything outside it.** No import of another project,
no CDN, no build step. Install it and it runs.

## Checking a change

```
python3 .github/check.py
```

Three things, none of which the file that breaks them looks wrong on its own
for: the JS parses, every `arAsset("x")` has a `relay/x` to serve, and every
call in an ASH file resolves to something that file or its imports define. That
last one matters most — a relay `.ash` that will not compile is served as a
bare 404, so the page simply stops existing and nothing says why.

## Licence

[BSD Zero Clause](LICENSE). Do anything you like with it, credit nobody, and
it comes with no warranty of any kind.
