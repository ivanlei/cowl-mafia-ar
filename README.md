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

## What it does

**Tickets.** Choose the items you use as tickets, from a dropdown of what you
hold — everything in your inventory, closet, display case and Hagnk's, with
how many and where, and anything untradeable flagged. The gCLI's `ar add`
takes any item by name or id, held or not. They are kept as item ids, so a
rename or a comma in a name cannot break the list.

**Default items** on that tab, or `ar defaultitems`, fills the list with **72
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
you are. **Restock** gathers the shortfall, lists it, and parks it at a price
nobody can pay — so that announcing a raffle later is one price change rather
than a scramble to list a dozen items while `/games` waits.

**Nothing here buys anything.** Every source moves something you already own
from one place you own to another, so hosting a raffle costs tickets and no
meat. The mall price is shown against each ticket, because an item worth more
than it sells for is the whole definition of one — but it is read, never used
to spend.

**Sales.** Sales of your tickets, newest first, filtered by item or by buyer
and sortable by any column.
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

## Settings

Ordinary KoLmafia preferences. Change them on the page, with `ar count` and
`ar sources`, or with `set`.

| Preference | Default | |
|---|---|---|
| `arTicketItems` | empty | the chosen items, as ids |
| `arRestockCount` | `11` | how many of each to hold |
| `arParkPrice` | `999999999999` | the price restock parks at (KoL's ceiling) |
| `arSources` | `inventory,closet,display,storage` | where restocking may draw from |

Those four are all of them. There is no fifth that buys.


## Install

KoLmafia installs it itself. The repository is private, so the URL has to carry
a token — and KoLmafia's gCLI writes every command it runs into the session
log, so do not type a token into it where that matters to you.

```
git checkout https://<token>@github.com/ivanlei/cowl-mafia-ar.git
```

`git update` afterwards. KoLmafia installs by folder name — `relay/` and
`scripts/` — which is why they sit at the top rather than under a `src/`.

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
```

Two things about the layout are load-bearing rather than taste:

**Every file is `ar`-prefixed.** KoLmafia resolves `import <x.ash>` by
searching the root, `scripts/`, `planting/` and `relay/` and taking the single
match (`KoLmafiaCLI.findScriptFile`). Two files of the same name anywhere in
one KoLmafia installation is not a shadowing, it is a hard *too many matches*
error — and another project installs into these same two folders.

**The core lives in `scripts/` and is imported from `relay/`.** That same
search is what lets one copy of the logic serve both the page and the command.

**Nothing here depends on anything outside it.** No import of another project,
no CDN, no build step. Another project solved some of the same problems first
and the comments say so where a rule came from there, but not a line of it is
required for this to run.

## Checking a change

```
python3 .github/check.py
```

Three things, none of which the file that breaks them looks wrong on its own
for: the JS parses, every `arAsset("x")` has a `relay/x` to serve, and every
call in an ASH file resolves to something that file or its imports define. That
last one matters most — a relay `.ash` that will not compile is served as a
bare 404, so the page simply stops existing and nothing says why.
