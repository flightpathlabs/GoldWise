# Changelog

What changed in each release of Goldwise, newest first. Work that hasn't
been released yet is listed under "Unreleased" in the copy of this file on
the `dev` branch.

## Unreleased

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
