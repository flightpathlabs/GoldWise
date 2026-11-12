local _, ns = ...

-- The First Aid recipes that vendors sell in WoW: Forever.
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

ns.RecipeData["First Aid"] = {
    { 16084, 7924, 125, vendors = { { 2805, 45, "Alliance" }, { 13476, 15, "Horde" } } },
    { 16112, 7929, 180, vendors = { { 2805, 45, "Alliance" }, { 13476, 15, "Horde" } } },
    { 16113, 10840, 210, vendors = { { 2805, 45, "Alliance" }, { 13476, 15, "Horde" } } },
    { 255729, 1244436, 275, vendors = { { 266901, 616 } } },
    {
        19442,
        23787,
        300,
        bound = true,
        standing = { 529, 6 },
        vendors = { { 10856, 85 }, { 10857, 28 }, { 11536, 139 } },
    },
    { 232434, 470349, 300, vendors = { { 17068, 1377, "Alliance" }, { 17070, 1377, "Horde" } } },
}
