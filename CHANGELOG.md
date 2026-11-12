# Changelog

What changed in each release of Goldwise, newest first. Work that hasn't
been released yet is listed under "Unreleased" in the copy of this file on
the `dev` branch.

## Unreleased

- **A Profit tab.** A line chart of what you came out ahead or behind by
  on each of the last 30 days, with the auction house on its own line,
  and a button to see it as a running total. It shows what you sold at
  auction, what you spent there on purchases and deposits, and your
  latest sales and purchases. Goldwise starts counting from this version:
  auction sales and purchases from before it aren't there.

- **A crafting tree for anything you can make.** Alt-right-click an item
  you can make, or make something from, to see the whole chain: what it
  takes, what those take, and what it goes into. Each step shows its
  auction price, what it costs to buy and what it costs to make, and the
  page says what you'd clear by buying the materials, making it and
  selling it. Click a row to follow the chain. `/gw tree`, a new key
  binding, the Assets right-click menu and the price history page open
  it as well.

- **Listing deposits are weighed as a risk, not a fee.** You get the
  deposit back when an auction sells and lose it when it doesn't, so
  Goldwise now asks whether the gain over a vendor is worth that stake,
  assuming one listing in three comes back unsold. Things with a decent
  margin that used to say "vendor" now say "sell".
- **What listing costs is measured, not assumed.** Goldwise used to take
  the deposit to be a flat 1 silver. It now asks the game each time you
  open the auction house, so it follows the minimum when Blizzard changes
  it (a drop to 1 copper has been announced), and it knows that things a
  vendor pays well for take a bigger deposit. It says so in chat when the
  minimum moves.
- **"What materials are worth" fills in as it goes.** The game has to be
  asked about each material, and answers slowly. The list used to show a
  page of "Looking it up..." while it waited. It now shows each kind as
  soon as it's ready, top to bottom, with a bar saying how far it has got,
  and gives up on anything the game never answers for.
- **Materials can be narrowed down.** A new menu on that page shows one
  kind at a time, with up to 30 of it, and the list keeps to what's within
  reach of your level unless you untick that.
- **Buying to sell shows its working.** Each line now has the vendor's
  price and the auction price beside the profit.
- **Places sends you to the trainer you need next.** A craft's trainers
  each teach one stretch of it, and the nearest tailor may be one you've
  outgrown. Places now picks the nearest who can take you further at
  your skill, and says so when it doesn't know of one. Trainers you
  visit are remembered one by one, with their titles.
- **Assets adds it all up.** A line under the list says what your things
  are worth at today's auction prices, on this character and across the
  account.

## 0.3.2 (11 November 2026)

- Carries its CurseForge project ID, so addon managers can match an
  installed copy to the listing, and new releases reach CurseForge on
  their own.
- Nothing else in the addon has changed.

## 0.3.1 (11 November 2026)

- Packaged the way CurseForge, Wago and addon managers expect, so it can
  be installed and kept up to date from them once it's listed there.
- Published as an ordinary release. Most addon managers hide anything
  marked as a pre-release unless you ask for it, which would have hidden
  Goldwise from nearly everyone. It is still a beta: expect rough edges.
- Nothing in the addon itself has changed since 0.3.0-beta.

## 0.3.0-beta (11 November 2026)

The first public beta. It was built and tested on one faction of one
ruleset, on an English client, so expect rough edges and please
[say what you find](https://github.com/flightpathlabs/GoldWise/issues/new/choose).

**What's in it**

- **Assets.** Everything you hold across your characters and their banks,
  with what it's worth and one line on what to do with it: auction it,
  vendor it, keep it. Right-click anything to keep it off the list. The
  tools of your trades are kept without asking.
- **Prospects.** Say what you want to do and get a plan in order: gather
  near your level, turn what you have into something worth more, buy from
  vendors and sell at auction, or make the most of the zone you're in.
- **Purse.** What you earn and spend by day, and what's coming: training
  for your next levels, repairs, and which city trains you cheapest.
- **Places.** The nearest trainer and service of every kind, with a
  button that opens the map there.
- **Recipes.** The vendor recipes your professions haven't learned, and a
  card when one is for sale close by.
- **Price history.** A chart on item tooltips, and a full history for
  anything you point at. Bind a key to it, or type `/gw` and an item link.
- **At the auction house.** Goldwise reads prices while the window is
  open, shows how far along it is, and stands aside when you search.
- **In your bags and bank.** A gold rim on what's worth auctioning.
- **When something goes wrong.** `/gw report` gathers what a bug report
  needs into one box to copy.

**Good to know**

- Nothing needs setting up. Prices come from your own visits to the
  auction house, so the advice gets better the more you play.
- Goldwise never posts, buys or cancels anything for you.
- It steps back where another addon is already showing the same thing,
  and reads along with another addon's full scan instead of spending the
  account's cooldown on its own.
- Price history is kept for 90 days unless you choose otherwise in the
  settings.
