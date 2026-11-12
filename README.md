# Goldwise

A clear guide to buying and selling in World of Warcraft: Forever.

Goldwise keeps a price history for the things you carry and tells you, in
a sentence, what's worth doing with each of them. It reads the auction
house when you open it, remembers what it saw, and stays quiet the rest of
the time.

This is an early version. It watches and advises; it does not post, buy or
cancel anything.

## Using it

Open the window with `/goldwise`, or pick Goldwise from the addon list by
the minimap.

Visit an auction house. Goldwise reads the prices in about fifteen
seconds and steps aside if you start a search of your own. After that the
window lists what's in your bags with:

- the lowest price and how many are listed
- a two-week trend line, once there's history to draw
- a verdict (Sell, Hold or Vendor) and the reason for it

Click a row for a month of price history.

Options are under **Options > AddOns > Goldwise**. "Auditor mode" has the
goblin deliver the same advice at full volume.

## How it decides

The rules are cautious on purpose:

- If a stack is worth less than the 1 silver listing deposit, vendor it.
- If the auction house would pay no more than a vendor after its cut,
  vendor it.
- If the gain over a vendor is smaller than the deposit you'd lose if it
  didn't sell, vendor it.
- Otherwise sell, unless the price is well below its usual level, in which
  case hold.

"Usual" needs at least four days of history. Until then the advice says
so rather than guessing.

## What it stores

One saved-variables file, `GoldwiseDB`:

- **Tracked items** (what you carry): daily low, high, last price and
  quantity, kept for 180 days.
- **Everything else**: one compact snapshot of the whole market per day,
  kept for 10 days.

Prices are filed per market. Forever has one auction house per region,
ruleset and faction, plus a neutral one, and Goldwise keeps them apart.

## For contributors

```
Core/      startup, events, saved data
Data/      tables: what can be gathered and where, and what trainers charge
Market/    which auction house we're at, the request queue, the scanners, the price feed
Ledger/    price storage and the sums done over it
Profile/   what the player and their other characters carry and can do
Advisor/   the rules that turn facts into advice (no game calls)
UI/        the window, lists, chart, tooltips and options page
Media/     icon and portrait
```

Files load in the order listed in `Goldwise.toc`, and each group only
uses what the groups above it define. Modules talk to each other through
the small message bus in `Core/Events.lua`; the list of messages is at the
bottom of that file.

Formatting is StyLua and linting is luacheck, both configured at the
repository root.

## Disclaimer

Goldwise is a free, fan-made addon. Its goblin mascot is an original
cartoon character and the branding is a joke. Any resemblance to real
people, shows, apps or companies is parody, and Goldwise is not affiliated
with, endorsed by or sponsored by any of them. It offers advice about a
video game's auction house and nothing else: none of it is financial
advice.

World of Warcraft and related names and artwork are trademarks of Blizzard
Entertainment. This project is not affiliated with or endorsed by Blizzard
Entertainment.

## Licence

MIT. See [LICENSE](LICENSE).

The class training prices in `Data/Training/` come from What's Training? by
Sveng, also MIT licensed. Its licence and the details are in
[THIRD-PARTY.md](THIRD-PARTY.md). Those files are written by the workshop's
`import-training.mjs` and shouldn't be edited by hand.
