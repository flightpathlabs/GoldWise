# Changelog

What changed in each release of Goldwise, newest first. Work that hasn't
been released yet is listed under "Unreleased" in the copy of this file on
the `dev` branch.

## Unreleased

**New**

- **Dismiss a recipe from the recipe card.** Each recipe on the "for
  sale here" card has a small X beside it. Click it and Goldwise stops
  mentioning that recipe; the card closes up and shows the next one. The
  recipe stays on the Recipes tab. The options page lists what you've
  dismissed and has a button to bring them all back.
- **A session tracker.** A small panel to keep on screen while you play,
  put there with the new Session tracker button on the Goldwise window's
  title bar, `/gw session`, or the options. It leads with what this
  session has made or lost in coin. Under that, where the coin came from
  and went: looted, quest rewards, sold to vendors, auction sales, and on
  the other side repairs, vendors, training, flights and the rest. Then
  what your bags would fetch if sold, at auction and to vendors, each with
  how far it has moved since the session began. Your bags aren't in the
  total, so something bought from a vendor shows as spent; the cog on the
  panel can count them in, and switches each section on or off. The arrow
  starts the session again, say before a run, and the button beside it
  folds the panel to a single line with the total. Click a line to open
  your purse or this character's assets. Drag it where you like;
  right-click to lock it. A reload, or logging back in within a quarter
  of an hour, carries on the same session. The pin in its corner opens
  Places, and pointing at it names the nearest auction house, repairs,
  bank, flight master and inn.
- **Goldwise's cards can be moved.** Drag the card that tells you about a
  recipe for sale nearby, or any other, to wherever you'd like them to
  appear, and they'll come up there from then on. Right-click one to put
  it back. The options have a button that puts one out to place. A card
  no longer puts itself away while you're pointing at it.
- **A cog for the options.** The Goldwise window has a settings cog
  beside its close button.
- **Any one character, or the whole account.** Purse and Profit now show
  the character you're playing, with a button beside each tab's menu to
  switch both to any of your other characters or to the whole account.
  Each character's own figures start from this version, so they fill in
  as you play, and an empty one says so; the whole account keeps
  everything it had. If you've only ever played one character with
  Goldwise, what they earned, spent and sold before carries straight
  over. Across the account, the latest sales name the character who
  made them.

**Better**

- **Purse tells more kinds of money apart.** Coin you loot, quest
  rewards and repairs are now kept apart from everything else, so the
  "mostly ..." line under spending can say repairs rather than "repairs
  and supplies". Earlier days stay as they were recorded.
- **A note on what's new.** The first time you open Goldwise after an
  update, a short note beside the window says what's changed, once.
  `/gw news` brings it back.

**Fixed**

- **Recipes are named on the recipe card.** A recipe the game hadn't
  fetched yet showed as "Recipe". It now shows the name of what it
  teaches straight away, and the recipe's own name once the game has it.
  The Recipes tab does the same.
- **Deposits that come back no longer count as spent.** When something
  sells, the auction house hands its deposit back in the sale's letter.
  Goldwise counted that letter as sold and kept the deposit as spending,
  so the Profit tab showed deposits as a cost after they'd been repaid.
  Now a sale's deposit comes off the deposits, and "Sold at auction" is
  what sales made after the cut. The profit figure was right before and
  hasn't changed. Sales from before this version stay as they were
  recorded.
- **"Make room" counts only your ordinary bags.** Empty slots in a
  quiver, ammo pouch or herb bag were counted as room for loot, so the
  reminder could stay quiet with your bags all but full.
- **"What materials are worth" keeps up.** It changed only after a read
  of the whole market. Prices from a search, the feed or other players
  now show there too, within half a minute.
- **Sharing a price over 214,000 gold**, as a joke listing might be, no
  longer goes wrong.
- "1 minutes ago" now reads "2 minutes ago".

## 0.4.0 (12 November 2026)

**New**

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
- **The verdict is on the tooltip.** Point at anything in your bags and
  Goldwise's line says Sell, Hold, Vendor or Keep, as the Assets tab
  would. It has a switch of its own in the options.
- **Auctionator's prices fill the gaps.** If you have Auctionator,
  Goldwise asks it, through the interface Auctionator offers other
  addons, for the last price of anything Goldwise has never priced
  itself: things Auctionator saw before Goldwise was installed, say.
  It's one price per item, so charts still fill in from your own visits,
  and the item's page says when a price is Auctionator's. Auctionator
  keeps one list for both factions, so its prices are only used for your
  own side's auction house, never over a price of Goldwise's own, and
  never passed on to other Goldwise players.
- **About lists the addons Goldwise works with**, and what it does
  differently beside each.
- **Point at the goblin in the corner of the window** and a tooltip says
  what Goldwise is, and which version you have.

**Better**

- **A day is now your day.** Goldwise counted days by the game's clock,
  which turns over in the middle of the afternoon in America and the
  middle of the morning in Australia. An evening's play and the next
  morning's landed on the same day, and the charts didn't move on. Days
  now run from midnight to midnight on your own clock, on every chart.
  Records from before the change sit a few hours out of place on their
  last day.
- **Every visit to the auction house counts, however short.** When
  Auctionator or Profession Atlas reads the market as you open the
  window, Goldwise reads along. It used to keep only the first 500
  prices unless that read ran to the end, so walking away after a few
  seconds left most of your things on their old price. It now keeps
  every page as it arrives. The same goes for Goldwise's own reads.
- **Fewer requests to the auction house when other addons are reading
  it.** When another addon asks for every auction, as Profession Atlas
  does, Goldwise now waits for that answer and uses it instead of reading
  the market itself at the same moment. If its own read is already under
  way when the list arrives, it stops. With Auctionator or Profession
  Atlas installed it also gives them a few seconds' head start on
  opening, so one read serves both.
- **Goldwise's tooltip lines say they're Goldwise's.** With several
  addons writing on the same tooltip, there was no telling which line
  was whose. Its line, the count your other characters hold, the
  crafting tree hint and the chart are now all marked with its name.
- **A price where the other addon has none.** Goldwise left tooltip
  prices to Auctionator whenever Auctionator was installed, so beside it
  there was often nothing of Goldwise's at all. It now asks whether
  Auctionator has a price for the item, and shows its own when it
  hasn't.
- **The tooltip chart appears after two days of prices**, not three.
- **Professions are recognised in any language.** They were matched by
  their English names, so on a German or French client Goldwise thought
  you had none. The rest of Goldwise is still in English.
- **A bid handed back is recognised in any language**, from the wording
  of the letter's subject, not only from the sender's English name.
- New releases reach Wago Addons as well as CurseForge.

**Fixed**

- **Roleplay-PvP worlds get a market of their own.** Their realm name
  ends in two words, and Goldwise read only the last, which filed their
  prices with the PvP worlds' and had the two swapping prices between
  players. If you play on one, your price history starts afresh under
  the right market.

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
