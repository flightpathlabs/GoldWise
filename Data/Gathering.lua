local _, ns = ...

-- What can be gathered, by whom, and roughly where.
--
-- This is the starting knowledge behind the Prospects tab. It was written
-- by hand from how these materials have worked since Classic, and Forever
-- is built on that world, but nothing here has been checked against
-- Forever's own data yet. Treat the level ranges as "about right". The
-- plan is to correct them from what players actually loot.
--
-- Prices are deliberately absent. Those come from the ledger.

local Gathering = {}
ns.Gathering = Gathering

-- Anyone can farm cloth. It drops from humanoids in these level ranges.
Gathering.CLOTH = {
    { itemID = 2589, name = "Linen Cloth", minLevel = 1, maxLevel = 18 },
    { itemID = 2592, name = "Wool Cloth", minLevel = 14, maxLevel = 30 },
    { itemID = 4306, name = "Silk Cloth", minLevel = 28, maxLevel = 42 },
    { itemID = 4338, name = "Mageweave Cloth", minLevel = 40, maxLevel = 52 },
    { itemID = 14047, name = "Runecloth", minLevel = 50, maxLevel = 60 },
}

-- Skinning. What comes off a beast depends on its level.
Gathering.SKINNING = {
    { itemID = 2318, name = "Light Leather", minLevel = 1, maxLevel = 20 },
    { itemID = 783, name = "Light Hide", minLevel = 10, maxLevel = 20 },
    { itemID = 2319, name = "Medium Leather", minLevel = 15, maxLevel = 30 },
    { itemID = 4232, name = "Medium Hide", minLevel = 15, maxLevel = 30 },
    { itemID = 4234, name = "Heavy Leather", minLevel = 25, maxLevel = 40 },
    { itemID = 4235, name = "Heavy Hide", minLevel = 25, maxLevel = 40 },
    { itemID = 4304, name = "Thick Leather", minLevel = 35, maxLevel = 50 },
    { itemID = 8169, name = "Thick Hide", minLevel = 35, maxLevel = 50 },
    { itemID = 8170, name = "Rugged Leather", minLevel = 45, maxLevel = 60 },
    { itemID = 8171, name = "Rugged Hide", minLevel = 45, maxLevel = 60 },
}

-- Mining. skill is what the vein needs; the levels are the zones it's
-- usually found in. Stone comes out of the same veins as the ore above it.
Gathering.MINING = {
    { itemID = 2770, name = "Copper Ore", skill = 1, minLevel = 1, maxLevel = 25 },
    { itemID = 2835, name = "Rough Stone", skill = 1, minLevel = 1, maxLevel = 25 },
    { itemID = 2771, name = "Tin Ore", skill = 65, minLevel = 15, maxLevel = 35 },
    { itemID = 2836, name = "Coarse Stone", skill = 65, minLevel = 15, maxLevel = 35 },
    { itemID = 2775, name = "Silver Ore", skill = 75, minLevel = 20, maxLevel = 40 },
    { itemID = 2772, name = "Iron Ore", skill = 125, minLevel = 28, maxLevel = 45 },
    { itemID = 2838, name = "Heavy Stone", skill = 125, minLevel = 28, maxLevel = 45 },
    { itemID = 2776, name = "Gold Ore", skill = 155, minLevel = 30, maxLevel = 50 },
    { itemID = 3858, name = "Mithril Ore", skill = 175, minLevel = 38, maxLevel = 55 },
    { itemID = 7912, name = "Solid Stone", skill = 175, minLevel = 38, maxLevel = 55 },
    { itemID = 7911, name = "Truesilver Ore", skill = 230, minLevel = 40, maxLevel = 60 },
    { itemID = 10620, name = "Thorium Ore", skill = 245, minLevel = 45, maxLevel = 60 },
    { itemID = 12365, name = "Dense Stone", skill = 245, minLevel = 45, maxLevel = 60 },
}

-- Herbalism, laid out the same way.
Gathering.HERBALISM = {
    { itemID = 2447, name = "Peacebloom", skill = 1, minLevel = 1, maxLevel = 20 },
    { itemID = 765, name = "Silverleaf", skill = 1, minLevel = 1, maxLevel = 20 },
    { itemID = 2449, name = "Earthroot", skill = 15, minLevel = 5, maxLevel = 20 },
    { itemID = 785, name = "Mageroyal", skill = 50, minLevel = 10, maxLevel = 25 },
    { itemID = 2450, name = "Briarthorn", skill = 70, minLevel = 10, maxLevel = 30 },
    { itemID = 3820, name = "Stranglekelp", skill = 85, minLevel = 15, maxLevel = 40 },
    { itemID = 2453, name = "Bruiseweed", skill = 100, minLevel = 15, maxLevel = 35 },
    { itemID = 3355, name = "Wild Steelbloom", skill = 115, minLevel = 20, maxLevel = 40 },
    { itemID = 3369, name = "Grave Moss", skill = 120, minLevel = 20, maxLevel = 40 },
    { itemID = 3356, name = "Kingsblood", skill = 125, minLevel = 20, maxLevel = 45 },
    { itemID = 3357, name = "Liferoot", skill = 150, minLevel = 25, maxLevel = 45 },
    { itemID = 3818, name = "Fadeleaf", skill = 160, minLevel = 30, maxLevel = 50 },
    { itemID = 3821, name = "Goldthorn", skill = 170, minLevel = 30, maxLevel = 50 },
    { itemID = 3358, name = "Khadgar's Whisker", skill = 185, minLevel = 35, maxLevel = 50 },
    { itemID = 3819, name = "Wintersbite", skill = 195, minLevel = 30, maxLevel = 40 },
    { itemID = 4625, name = "Firebloom", skill = 205, minLevel = 40, maxLevel = 55 },
    { itemID = 8831, name = "Purple Lotus", skill = 210, minLevel = 40, maxLevel = 55 },
    { itemID = 8836, name = "Arthas' Tears", skill = 220, minLevel = 45, maxLevel = 60 },
    { itemID = 8838, name = "Sungrass", skill = 230, minLevel = 45, maxLevel = 60 },
    { itemID = 8839, name = "Blindweed", skill = 235, minLevel = 45, maxLevel = 55 },
    { itemID = 8845, name = "Ghost Mushroom", skill = 245, minLevel = 45, maxLevel = 55 },
    { itemID = 8846, name = "Gromsblood", skill = 250, minLevel = 48, maxLevel = 58 },
    { itemID = 13464, name = "Golden Sansam", skill = 260, minLevel = 50, maxLevel = 60 },
    { itemID = 13463, name = "Dreamfoil", skill = 270, minLevel = 50, maxLevel = 60 },
    { itemID = 13465, name = "Mountain Silversage", skill = 280, minLevel = 53, maxLevel = 60 },
    { itemID = 13466, name = "Plaguebloom", skill = 285, minLevel = 50, maxLevel = 60 },
    { itemID = 13467, name = "Icecap", skill = 290, minLevel = 55, maxLevel = 60 },
}

-- Outdoor zones and the levels they suit. mapID is the world-map ID, which
-- is also what lets us open the map there. A zone with a faction is that
-- side's territory, and we don't send the other side into it.
Gathering.ZONES = {
    { mapID = 1426, minLevel = 1, maxLevel = 10, faction = "Alliance" }, -- Dun Morogh
    { mapID = 1429, minLevel = 1, maxLevel = 10, faction = "Alliance" }, -- Elwynn Forest
    { mapID = 1438, minLevel = 1, maxLevel = 10, faction = "Alliance" }, -- Teldrassil
    { mapID = 1411, minLevel = 1, maxLevel = 10, faction = "Horde" }, -- Durotar
    { mapID = 1412, minLevel = 1, maxLevel = 10, faction = "Horde" }, -- Mulgore
    { mapID = 1420, minLevel = 1, maxLevel = 10, faction = "Horde" }, -- Tirisfal Glades
    { mapID = 1436, minLevel = 10, maxLevel = 20, faction = "Alliance" }, -- Westfall
    { mapID = 1432, minLevel = 10, maxLevel = 20, faction = "Alliance" }, -- Loch Modan
    { mapID = 1439, minLevel = 10, maxLevel = 20, faction = "Alliance" }, -- Darkshore
    { mapID = 1421, minLevel = 10, maxLevel = 20, faction = "Horde" }, -- Silverpine Forest
    { mapID = 1413, minLevel = 10, maxLevel = 25, faction = "Horde" }, -- The Barrens
    { mapID = 1433, minLevel = 15, maxLevel = 25, faction = "Alliance" }, -- Redridge Mountains
    { mapID = 1442, minLevel = 15, maxLevel = 27 }, -- Stonetalon Mountains
    { mapID = 1431, minLevel = 18, maxLevel = 30, faction = "Alliance" }, -- Duskwood
    { mapID = 1440, minLevel = 18, maxLevel = 30 }, -- Ashenvale
    { mapID = 1437, minLevel = 20, maxLevel = 30, faction = "Alliance" }, -- Wetlands
    { mapID = 1424, minLevel = 20, maxLevel = 30 }, -- Hillsbrad Foothills
    { mapID = 1441, minLevel = 25, maxLevel = 35 }, -- Thousand Needles
    { mapID = 1416, minLevel = 30, maxLevel = 40 }, -- Alterac Mountains
    { mapID = 1417, minLevel = 30, maxLevel = 40 }, -- Arathi Highlands
    { mapID = 1443, minLevel = 30, maxLevel = 40 }, -- Desolace
    { mapID = 1434, minLevel = 30, maxLevel = 45 }, -- Stranglethorn Vale
    { mapID = 1445, minLevel = 35, maxLevel = 45 }, -- Dustwallow Marsh
    { mapID = 1418, minLevel = 35, maxLevel = 45 }, -- Badlands
    { mapID = 1435, minLevel = 35, maxLevel = 45 }, -- Swamp of Sorrows
    { mapID = 1446, minLevel = 40, maxLevel = 50 }, -- Tanaris
    { mapID = 1444, minLevel = 40, maxLevel = 50 }, -- Feralas
    { mapID = 1425, minLevel = 40, maxLevel = 50 }, -- The Hinterlands
    { mapID = 1427, minLevel = 43, maxLevel = 50 }, -- Searing Gorge
    { mapID = 1447, minLevel = 45, maxLevel = 55 }, -- Azshara
    { mapID = 1419, minLevel = 45, maxLevel = 55 }, -- Blasted Lands
    { mapID = 1449, minLevel = 48, maxLevel = 55 }, -- Un'Goro Crater
    { mapID = 1448, minLevel = 48, maxLevel = 55 }, -- Felwood
    { mapID = 1428, minLevel = 50, maxLevel = 58 }, -- Burning Steppes
    { mapID = 1422, minLevel = 51, maxLevel = 58 }, -- Western Plaguelands
    { mapID = 1423, minLevel = 53, maxLevel = 60 }, -- Eastern Plaguelands
    { mapID = 1452, minLevel = 53, maxLevel = 60 }, -- Winterspring
    { mapID = 1451, minLevel = 55, maxLevel = 60 }, -- Silithus
}
