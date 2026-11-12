local _, ns = ...

-- The Fishing recipes that vendors sell in WoW: Forever.
--
-- Written by tools/import-whats-training.mjs from What's Training? 11.4.3
-- by Sveng, used under the MIT licence (see THIRD-PARTY.md). Don't edit
-- this by hand: run the importer again when that addon updates.
--
-- Each recipe is { the item sold, the spell it teaches, skill needed },
-- and then, where they apply:
--   bound     true if it binds when bought, so it can't be sold on
--   favor     its price in Merchant's Favor, for those not sold for coin
--   standing  { faction ID, standing, ... }: the reputation it takes to
--             buy it, as pairs. Meeting any one pair is enough.
--   vendors   { NPC ID, area ID, side }, side given only for vendors who
--             deal with one side alone

ns.RecipeData["Fishing"] = {
    { 16083, 7732, 125, vendors = { { 2626, 33 } } },
}
