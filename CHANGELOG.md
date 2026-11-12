# Changelog

What changed in each release of Goldwise, newest first. Work that hasn't
been released yet is listed under "Unreleased" in the copy of this file on
the `dev` branch.

## Unreleased

- **A day is now your day.** Goldwise counted days by the game's clock,
  which turns over in the middle of the afternoon in America and the
  middle of the morning in Australia. An evening's play and the next
  morning's landed on the same day, and the charts didn't move on. Days
  now run from midnight to midnight on your own clock, on every chart.
  Records from before the change sit a few hours out of place on their
  last day.
- **The Purse chart can be cut finer.** A menu at the top of the tab
  sets how long a stretch each bar covers: a day, twelve hours, six, or
  one. Your choice is remembered.
- **Coin held, as a line.** The same menu swaps the bars for a line of
  what your characters held between them, stretch by stretch. It starts
  from this version: what you held before isn't on record.
- **An item's price within the day.** The price history page has a menu
  of its own: a point a day, as before, or every separate reading over
  the last week or the last two days. Prices that swing between morning
  and evening show up there. Goldwise keeps three times as many readings
  of each thing you hold as it did.
- **Fewer requests to the auction house when other addons are reading
  it.** When another addon asks for every auction, as Profession Atlas
  does, Goldwise now waits for that answer and uses it instead of reading
  the market itself at the same moment. If its own read is already under
  way when the list arrives, it stops. With Auctionator or Profession
  Atlas installed it also gives them a few seconds' head start on
  opening, so one read serves both.
- **About lists the addons Goldwise works with**, and what it does
  differently beside each.
- **Professions are recognised in any language.** They were matched by
  their English names, so on a German or French client Goldwise thought
  you had none. The rest of Goldwise is still in English.
- **A bid handed back is recognised in any language**, from the wording
  of the letter's subject, not only from the sender's English name.
- **Roleplay-PvP worlds get a market of their own.** Their realm name
  ends in two words, and Goldwise read only the last, which filed their
  prices with the PvP worlds' and had the two swapping prices between
  players. If you play on one, your price history starts afresh under
  the right market.
- Carries its Wago Addons project ID, so new releases reach Wago as well
  as CurseForge.

## 0.3.3 (12 November 2026)

**New**

- **A Profit tab.** A line chart of what you came out ahead or behind by
  on each of the last 30 days, with the auction house on its own line.
  It can show the same days as a running total, or what you're worth:
  your coin and your goods across your characters, day by day. Above the
  chart is what you sold at auction and what you spent there on purchases
  and deposits; below it, your latest sales and purchases. Goldwise
  starts counting from this version: auction sales and purchases from
  before it aren't there.
- **A crafting tree for anything you can make.** Alt-right-click an item
  you can make, or make something from, to see the whole chain: what it
  takes, what those take, and what it goes into. Each step shows its
  auction price, what it costs to buy and what it costs to make. The page
  says what you'd clear by buying the materials, making it and selling
  it, and the price it has to fetch to cover them. Click a row to follow
  the chain. `/gw tree`, the Assets right-click menu and the price
  history page open it as well.
- **A Shortcuts page in the options.** Choose which click opens the
  crafting tree, and give it and the price history a key each, by
  pressing the key. The page warns you when the click or the key is
  already used for something else, and asks before taking a key over.

**Better**

- **Listing deposits are weighed as a risk, not a fee.** You get the
  deposit back when an auction sells and lose it when it doesn't, so
  Goldwise now asks whether the gain over a vendor is worth that stake,
  assuming one listing in three comes back unsold. Things with a decent
  margin that used to say "vendor" now say "sell".
- **What listing costs is measured, not assumed.** Goldwise used to take
  the deposit to be a flat 1 silver. It now asks the game each time you
  open the auction house, so it follows the minimum when Blizzard changes
  it (a drop to 1 copper has been announced), and it knows that things a
  vendor pays well for take a bigger deposit.
- **Places sends you to the trainer you need next.** A craft's trainers
  each teach one stretch of it, and the nearest tailor may be one you've
  outgrown. Places now picks the nearest who can take you further at
  your skill, and says so when it doesn't know of one. Trainers you
  visit are remembered one by one, with their titles.
- **Assets adds it all up.** A line under the list says what your things
  are worth at today's auction prices, on this character and across the
  account.
- **An item's page says more.** When its price rests on only a few
  listings, when you hold more of it than the whole market has listed,
  and what you last paid for it at auction against what it would clear
  today.
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
- **`/gw check` is a self-check.** It says whether the game offers what
  Goldwise needs, and what Goldwise has on record. Useful to send with a
  report.

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
