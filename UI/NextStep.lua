local _, ns = ...

-- The moments Goldwise speaks up without being asked.
--
--   * Arriving somewhere with an auction house, when a visit would
--     actually pay: prices have gone stale, or the bags hold something
--     worth listing.
--   * Opening a merchant while carrying things that would fetch a good
--     deal more at auction.
--   * Entering a zone where a vendor sells a recipe the player could use
--     and hasn't learned.
--   * The first time the window is opened after an update with news
--     worth telling a returning player (at the end of this file).
--
-- Each happens at most once per visit, the first three can be switched
-- off, and none fires in combat. The rest of the time the only sign is a
-- soft pulse on the minimap button.

local Theme = ns.Theme

-- Prices older than this are worth a trip to refresh.
local STALE_AFTER = 24 * 3600

-- Bags have to hold at least this much in sellable goods before we mention
-- them. Below it, the walk isn't worth it.
local WORTH_MENTIONING = 2000

-- At a merchant, only speak up for a stack that would clear at least this
-- much more at auction than the merchant pays.
local WORTH_KEEPING = 500

-- Things can happen in a rush on arrival (zone, resting state, bags), so
-- wait for them to settle before deciding anything.
local SETTLE_DELAY = 2

-- How near, in yards, counts as "close by". Wide enough to take in a
-- capital from gate to gate, but not an inn at the far end of a zone that
-- happens to share a map with a trading town.
local CLOSE_BY = 1000

-- Items pictured on the arrival card. Fewer than a card can hold: it's a
-- nudge, not an inventory.
local ITEMS_ON_ARRIVAL = 3

-- Whether we've already prompted during this stay in a rested area.
local promptedThisStay = false

local checkPending = false

-- The rows for a card: the first few of a list of assets, each with its
-- icon and a line saying why it's there.
local function CardItems(assets, limit, detailFor)
    local items = {}
    for index = 1, math.min(limit, #assets) do
        local asset = assets[index]
        items[index] = {
            itemID = asset.itemID,
            link = asset.link,
            icon = asset.icon,
            name = asset.name,
            quality = asset.quality,
            count = asset.count,
            detail = detailFor(asset),
        }
    end
    return items
end

-- Where auction houses are ----------------------------------------------------------

-- Nobody has to maintain a list. Wherever the player was standing when an
-- auction house opened, there's an auction house.
ns.Subscribe("AUCTION_HOUSE_OPENED", function()
    local mapID = C_Map.GetBestMapForUnit("player")
    local position = mapID and C_Map.GetPlayerMapPosition(mapID, "player")
    if position then
        local x, y = position:GetXY()
        ns.db.places[mapID] = { x = x, y = y }
    end

    -- They're here now. Nothing left to prompt about.
    promptedThisStay = true
    ns.Toast.Hide()
    ns.SetButtonAttention(false)
end)

-- Arriving near an auction house -----------------------------------------------------

-- Whether the player is within walking distance of a known auction house
-- on their current map.
local function IsCloseBy(mapID, place)
    local position = C_Map.GetPlayerMapPosition(mapID, "player")
    if not position then
        return false
    end

    -- Map positions are fractions of the map, and maps come in all sizes,
    -- so measure in the world's own yards.
    local _, here = C_Map.GetWorldPosFromMapPos(mapID, position)
    local _, there = C_Map.GetWorldPosFromMapPos(mapID, CreateVector2D(place.x, place.y))
    if not here or not there then
        -- Nothing to measure with. Sharing a map will have to do.
        return true
    end

    local hereX, hereY = here:GetXY()
    local thereX, thereY = there:GetXY()
    return (hereX - thereX) ^ 2 + (hereY - thereY) ^ 2 <= CLOSE_BY ^ 2
end

local function StalePricesText(marketKey)
    local lastScan = ns.Ledger.LastScan(marketKey)
    if not lastScan then
        return "You haven't read prices here yet"
    elseif GetServerTime() - lastScan > STALE_AFTER then
        return "Your prices were read " .. ns.Ago(GetServerTime() - lastScan)
    end
end

local function Check()
    checkPending = false

    if not IsResting() then
        -- Left town. The next arrival is a fresh visit.
        promptedThisStay = false
        ns.SetButtonAttention(false)
        return
    end

    local mapID = C_Map.GetBestMapForUnit("player")
    local place = mapID and ns.db.places[mapID]
    if not place or ns.Market.IsOpen() or not IsCloseBy(mapID, place) then
        ns.SetButtonAttention(false)
        return
    end

    local marketKey = ns.Market.Here()
    local stale = StalePricesText(marketKey)
    local assets, sellable = ns.Assets.InBags(marketKey)
    local worthSelling = sellable >= WORTH_MENTIONING

    local reason = stale ~= nil or worthSelling
    ns.SetButtonAttention(reason)

    if not reason or promptedThisStay or not ns.settings.cityPrompt then
        return
    end
    promptedThisStay = true

    local body
    if stale and worthSelling then
        body = ("%s, and you're carrying about %s worth selling."):format(
            stale,
            Theme.Coins(sellable)
        )
    elseif worthSelling then
        body = ("You're carrying about %s worth selling."):format(Theme.Coins(sellable))
    else
        body = stale .. ". A quick visit will bring them up to date."
    end

    -- Show the best of what they'd be selling, so the number isn't abstract.
    local toSell = {}
    if worthSelling then
        for _, asset in ipairs(assets) do
            if asset.advice.verb == ns.Advice.SELL and (asset.advice.proceeds or 0) > 0 then
                table.insert(toSell, asset)
            end
        end
        table.sort(toSell, function(a, b)
            return a.advice.proceeds > b.advice.proceeds
        end)
    end

    ns.Toast.Show({
        title = "The auction house is close by",
        body = body,
        items = CardItems(toSell, ITEMS_ON_ARRIVAL, function(asset)
            return ("About %s at auction"):format(Theme.Coins(asset.advice.proceeds))
        end),
        primary = {
            label = "Show me",
            onClick = function()
                ns.MapMarks.ShowPoint(mapID, place.x, place.y)
            end,
        },
        secondary = { label = "Not today" },
    })
end

local function CheckSoon()
    if not checkPending then
        checkPending = true
        C_Timer.After(SETTLE_DELAY, Check)
    end
end

ns.OnEvent("PLAYER_UPDATE_RESTING", CheckSoon)
ns.OnEvent("ZONE_CHANGED_NEW_AREA", CheckSoon)
ns.Subscribe("BAGS_CHANGED", CheckSoon)
ns.Subscribe("AUCTION_HOUSE_CLOSED", CheckSoon)

-- At a merchant ------------------------------------------------------------------------

local function CheckBeforeVendoring()
    if not ns.settings.vendorCheck then
        return
    end

    -- Everything that would clear a good deal more at auction than here.
    -- Things a merchant won't buy at all are in no danger.
    local worthKeeping = {}
    for _, asset in ipairs(ns.Assets.InBags(ns.Market.Home())) do
        local advice = asset.advice
        local fromVendor = advice.fromVendor or 0
        local gain = (advice.proceeds or 0) - fromVendor
        if advice.verb == ns.Advice.SELL and fromVendor > 0 and gain >= WORTH_KEEPING then
            asset.gain = gain
            table.insert(worthKeeping, asset)
        end
    end

    if #worthKeeping == 0 then
        return
    end

    table.sort(worthKeeping, function(a, b)
        return a.gain > b.gain
    end)

    local body = "They'd fetch a good deal more at the auction house."
    local unlisted = #worthKeeping - ns.Toast.MAX_ITEMS
    if unlisted > 0 then
        body = body .. (" %d more are on the Assets tab."):format(unlisted)
    end

    ns.Toast.Show({
        title = ns.settings.auditorMode and "Do NOT vendor these" or "Before you sell these",
        body = body,
        items = CardItems(worthKeeping, ns.Toast.MAX_ITEMS, function(asset)
            return ("%s at auction, only %s here"):format(
                Theme.Coins(asset.advice.proceeds),
                Theme.Coins(asset.advice.fromVendor)
            )
        end),
        primary = { label = "Got it" },
    })
end

ns.OnEvent("MERCHANT_SHOW", CheckBeforeVendoring)
ns.OnEvent("MERCHANT_CLOSED", ns.Toast.Hide)

-- Recipes for sale where the player is ---------------------------------------------------

-- Wait this long after arriving before mentioning recipes. Longer than
-- the auction house check takes, so that card gets to go first.
local RECIPE_DELAY = 6

-- If another card is up when we'd speak, wait this long and try again.
-- Once: after that the moment has passed.
local RECIPE_RETRY = 30

-- Zones we've already spoken up in this session. A recipe that wasn't
-- wanted the first time through town isn't wanted the second.
local recipesMentioned = {}

-- The recipe card while it's up: the card, the zone it's about, and the
-- recipes it's about, first shown first. Kept so the card can be redrawn
-- when a row is dismissed or a recipe's name arrives.
local recipeCard

local DISMISS_TIP = {
    "Don't mention this one again",
    "It stays on the Recipes tab. Goldwise's options can bring it back.",
}

local RecipeCardOptions

-- The X on one of the card's rows: that recipe is dropped for good, and
-- the card closes up, bringing on the next one if there are more.
local function DismissRecipe(recipe)
    ns.Recipes.Ignore(recipe)
    if not recipeCard then
        return
    end

    local remaining = {}
    for _, other in ipairs(recipeCard.recipes) do
        if other ~= recipe then
            table.insert(remaining, other)
        end
    end
    recipeCard.recipes = remaining

    if #remaining == 0 then
        ns.Toast.Hide()
        recipeCard = nil
    else
        ns.Toast.Update(recipeCard.id, RecipeCardOptions())
    end
end

function RecipeCardOptions()
    local zone, forSale = recipeCard.zone, recipeCard.recipes

    local items = {}
    for index = 1, math.min(ns.Toast.MAX_ITEMS, #forSale) do
        local recipe = forSale[index]
        local spot = ns.Recipes.VendorSpot(recipe)

        local detail = ("%s %d"):format(recipe.profession, recipe.needed)
        if not recipe.ready then
            detail = ("%s (you're at %d)"):format(detail, recipe.skill)
        end
        if spot and spot.name then
            detail = ("%s, from %s"):format(detail, spot.name)
        end

        items[index] = {
            itemID = recipe.item,
            icon = C_Item.GetItemIconByID(recipe.item),
            name = ns.Recipes.Name(recipe.item, recipe.spell),
            quality = C_Item.GetItemQualityByID(recipe.item),
            detail = detail,
            onDismiss = function()
                DismissRecipe(recipe)
            end,
            dismissTip = DISMISS_TIP,
        }
    end

    local body = #forSale == 1 and "A vendor in %s sells one you haven't learned."
        or "Vendors in %s sell some you haven't learned."
    body = body:format(zone)
    if #forSale > #items then
        body = body .. (" %d more are on the Recipes tab."):format(#forSale - #items)
    end

    return {
        title = ns.settings.auditorMode and "You are MISSING recipes" or "Recipes for sale here",
        body = body,
        items = items,
        primary = {
            label = "Show me",
            onClick = function()
                -- The vendor on the map if we can place them, and the
                -- full list either way.
                local spot = ns.Recipes.VendorSpot(forSale[1])
                if spot then
                    ns.MapMarks.ShowPoint(spot.mapID, spot.x, spot.y)
                else
                    ns.ShowWindowTab("Recipes")
                end
            end,
        },
        secondary = { label = "Not now" },
    }
end

-- A recipe's name can arrive after the card is up. The card shows the
-- spell's name until then, and swaps in the recipe's own when it comes.
ns.Subscribe("ITEM_NAMES_LOADED", function()
    if recipeCard and not ns.Toast.IsShowing() then
        recipeCard = nil
    elseif recipeCard then
        ns.Toast.Update(recipeCard.id, RecipeCardOptions())
    end
end)

local function CheckRecipes(isRetry)
    if not ns.settings.recipePrompt or InCombatLockdown() then
        return
    end

    local zone = GetRealZoneText()
    if not zone or zone == "" or recipesMentioned[zone] then
        return
    end

    local forSale = ns.Recipes.ForSaleHere()
    if #forSale == 0 then
        return
    end

    if ns.Toast.IsShowing() then
        if not isRetry then
            C_Timer.After(RECIPE_RETRY, function()
                CheckRecipes(true)
            end)
        end
        return
    end
    recipesMentioned[zone] = true

    recipeCard = { zone = zone, recipes = forSale }
    local shown = ns.Toast.Show(RecipeCardOptions())
    if shown then
        recipeCard.id = shown
    else
        recipeCard = nil
    end
end

local function CheckRecipesSoon()
    C_Timer.After(RECIPE_DELAY, function()
        CheckRecipes()
    end)
end

ns.OnEvent("ZONE_CHANGED_NEW_AREA", CheckRecipesSoon)
ns.OnEvent("PLAYER_ENTERING_WORLD", CheckRecipesSoon)

-- What's new ----------------------------------------------------------------------------

-- Once after an update, a note beside the Goldwise window saying what's
-- changed that a returning player would otherwise trip over. It waits
-- for the window to be opened rather than interrupting play, and comes
-- up only the once; /gw news brings it back. Someone installing Goldwise
-- for the first time has nothing to unlearn, so they never see one.
--
-- Each release with something worth saying gets an entry here, under a
-- name of its own. ns.db.newsSeen keeps the names of those already shown.
local NEWS = {
    {
        id = "0.4.1",
        title = "New in Goldwise",
        body = function()
            local lines = {}
            if not ns.Characters.IsOnlyOne() then
                table.insert(
                    lines,
                    "Purse and Profit now open on the character you're playing. Each "
                        .. "character's own figures start from this version, so they'll "
                        .. "look empty for a while. Everything from before is still there, "
                        .. "under Whole account: the button at the top of either tab."
                )
            end
            table.insert(
                lines,
                "There's also a session tracker to keep on screen: the Session button "
                    .. "on this window's title bar. And Goldwise's suggestion cards can be "
                    .. "dragged wherever you'd like them."
            )
            return table.concat(lines, "\n\n")
        end,
        -- A button that goes with what's new, if there is one.
        action = function()
            if ns.Characters.IsOnlyOne() then
                return nil
            end
            return {
                label = "See my history",
                onClick = function()
                    ns.settings.moneyAccountWide = true
                    ns.Publish("SETTINGS_CHANGED")
                    ns.ShowWindowTab("Purse")
                end,
            }
        end,
    },
}

local NEWS_WIDTH = 300
local NEWS_PADDING = 14

-- Whether this is someone coming from an earlier version. Decided before
-- anything has written to the saved data this session: an earlier
-- version will have left a purse there.
ns.Subscribe("DATABASE_READY", function()
    if type(ns.db.newsSeen) == "table" then
        return
    end

    ns.db.newsSeen = {}
    if type(ns.db.purse) ~= "table" then
        for _, news in ipairs(NEWS) do
            ns.db.newsSeen[news.id] = true
        end
    end
end)

local newsPanel

local function CreateNewsPanel(window)
    local panel = CreateFrame("Frame", nil, window, "TooltipBorderedFrameTemplate")
    panel:SetWidth(NEWS_WIDTH)
    panel:SetPoint("TOPLEFT", window, "TOPRIGHT", 4, -24)
    panel:SetClampedToScreen(true)
    -- It's been seen once the window has been open with it; closing the
    -- window any way at all puts it away.
    window:HookScript("OnHide", function()
        panel:Hide()
    end)
    panel:EnableMouse(true)

    local textWidth = NEWS_WIDTH - 2 * NEWS_PADDING

    panel.Title = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalMed3")
    panel.Title:SetPoint("TOPLEFT", NEWS_PADDING, -NEWS_PADDING)
    panel.Title:SetWidth(textWidth)
    panel.Title:SetJustifyH("LEFT")
    panel.Title:SetTextColor(unpack(Theme.COIN))

    panel.Body = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    panel.Body:SetPoint("TOPLEFT", panel.Title, "BOTTOMLEFT", 0, -8)
    panel.Body:SetWidth(textWidth)
    panel.Body:SetJustifyH("LEFT")
    panel.Body:SetSpacing(3)

    panel.Action = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    panel.Action:SetSize(130, 22)
    panel.Action:SetPoint("BOTTOMLEFT", NEWS_PADDING, NEWS_PADDING - 2)

    panel.Done = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    panel.Done:SetSize(90, 22)
    panel.Done:SetText("Got it")
    panel.Done:SetScript("OnClick", function()
        panel:Hide()
    end)

    return panel
end

local function ShowNewsPanel(window, news)
    newsPanel = newsPanel or CreateNewsPanel(window)
    newsPanel.Title:SetText(news.title)
    newsPanel.Body:SetText(news.body())

    local action = news.action()
    newsPanel.Action:SetShown(action ~= nil)
    newsPanel.Done:ClearAllPoints()
    if action then
        newsPanel.Action:SetText(action.label)
        newsPanel.Action:SetScript("OnClick", function()
            newsPanel:Hide()
            action.onClick()
        end)
        newsPanel.Done:SetPoint("LEFT", newsPanel.Action, "RIGHT", 8, 0)
    else
        newsPanel.Done:SetPoint("BOTTOMLEFT", NEWS_PADDING, NEWS_PADDING - 2)
    end

    local height = NEWS_PADDING + newsPanel.Title:GetStringHeight() + 8
    height = height + newsPanel.Body:GetStringHeight() + 14 + 22 + NEWS_PADDING
    newsPanel:SetHeight(height)
    newsPanel:Show()
end

--- Called as the Goldwise window opens: puts the news beside it if
--- there's some this player hasn't seen.
---@param window table  the main window
function ns.OfferNews(window)
    local news
    for _, entry in ipairs(NEWS) do
        if not ns.db.newsSeen[entry.id] then
            news = entry
        end
    end
    if not news then
        return
    end

    ShowNewsPanel(window, news)
    -- Only the newest is shown. Anything older has been overtaken.
    for _, entry in ipairs(NEWS) do
        ns.db.newsSeen[entry.id] = true
    end
end

--- Shows the latest news again, whether or not it's been seen. For
--- /gw news.
---@param window table  the main window, open
function ns.ShowNewsBeside(window)
    ShowNewsPanel(window, NEWS[#NEWS])
end
