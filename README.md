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

**Tickets.** Choose the items you use as tickets. The page searches every item
KoLmafia knows by name; the gCLI takes a name or an id. They are kept as item
ids, so a rename or a comma in a name cannot break the list.

**Stock.** For each ticket: how many are listed, at what price and limit, how
many each place you keep things could supply, and how far short of your target
you are. **Restock** gathers the shortfall, lists it, and parks it at a price
nobody can pay — so that announcing a raffle later is one price change rather
than a scramble to list a dozen items while `/games` waits.

**Sales.** Your store's sales log, newest first, filtered by item or by buyer.
Ticket sales are highlighted. This is the log you read the winner out of.

It does **not** announce, roll, pick the winner or send the prize. That half is
still yours.

## Using it

In the relay browser, **Scripts → Anti Raffle**. Or from the gCLI:

```
ar                     what you have chosen, and what is in the store
ar items               the chosen tickets
ar add <item>          choose one
ar remove <item>       unchoose one
ar stock               the store, source by source
ar restock [item]      list and park -- the one command that writes
ar count [n]           how many of each to hold (default 11)
ar sources [list]      where restocking may draw from
ar sales [filter]      what has sold, by item or buyer
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
| `arPriceLevel` | unset | falls back to `maximizerPriceLevel` |
| `arMaxPrice` | unset | falls back to `maximizerMaxPrice`, then `autoBuyPriceLimit` |

`mall` is not a default source, because every other one moves something you
already own and that one spends meat. Switch it on and restocking will buy the
shortfall, on the maximizer's terms: the two price controls above are read from
the maximizer and **never written back to it**, since `MaximizerFrame` reads
those preferences once when its window is built and writing them from here
would quietly change what the maximizer does the next time somebody runs it.

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
