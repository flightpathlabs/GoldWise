local _, ns = ...

-- The Items tab: find any item by name, and get from it to its price
-- history and crafting tree. Every other tab starts from something the
-- player has or could do; this one starts from whatever they're wondering
-- about.
--
-- The names come from Ledger\Names.lua, which writes down every name
-- Goldwise comes across. An item never seen can still be found by
-- shift-clicking a link to it into the box, or by its number.

local ItemsTab = {}
ns.ItemsTab = ItemsTab

local Theme = ns.Theme

local ROW_HEIGHT = 44

-- Fewer letters than this match too much to be worth listing.
local SHORTEST = 2

-- Rows listed at most. More than this and the player types another
-- letter rather than scroll.
local MOST_ROWS = 200

-- Typing is searched once it pauses for this long, not on every key.
local TYPING_PAUSE = 0.15

-- Columns are placed from the right edge, in pixels.
local TREE_RIGHT = 10
local TREE_WIDTH = 92
local VERDICT_RIGHT = 114
local PRICE_RIGHT = 190
local NAME_RIGHT = 316

-- What the list says when there's nothing in it, by why.
local NOTHING_TYPED = "Type part of a name, or shift-click an item into the box."
local TOO_SHORT = "Keep typing: one letter matches nearly everything."
local NO_MATCH = "Nothing Goldwise has seen goes by that name. "
    .. "Shift-click the item into the box to look it up."

local FOOTER = "Click an item for its price history; right-click for more. "
    .. "Names are learned as you come across items."

-- What a row says -------------------------------------------------------------

-- Works out an item's price and verdict as the Assets list would, for a
-- row the list is about to show. Only rows on screen ask, because it
-- means reading the price history, and a search can match hundreds.
local function Describe(data, cache)
    local described = cache[data.itemID]
    if described then
        return described
    end

    local itemID = data.itemID
    local holding = ns.Bags.Holding(itemID)
    described = ns.Assets.Describe(holding or {
        itemID = itemID,
        count = ns.Bags.Counts()[itemID] or 0,
    }, ns.Market.Current())

    -- A verdict is advice on what to do with something held and sellable.
    -- Anything else has a price to show, and nothing to advise.
    described.hasVerdict = holding ~= nil
    cache[itemID] = described
    return described
end

-- The line under the name.
local function DetailText(described)
    if described.hasVerdict then
        return described.advice.reason
    end

    local against = described.againstUsual
    if against and math.abs(against) >= 0.05 then
        return ("%d%% %s its usual price"):format(
            math.floor(math.abs(against) * 100 + 0.5),
            against > 0 and "above" or "below"
        )
    elseif described.seenAt then
        return "Last seen at auction " .. ns.Ago(GetServerTime() - described.seenAt)
    end
    return "No auction price on record"
end

-- The item's link, from the row or the client. Nil until the client has
-- loaded the item, which is fine: everything that takes one makes do
-- with the ID.
local function LinkOf(data)
    return data.link or select(2, C_Item.GetItemInfo(data.itemID))
end

-- Rows ------------------------------------------------------------------------

local function CreateRowWidgets(row)
    row.created = true

    row.Stripe = row:CreateTexture(nil, "BACKGROUND")
    row.Stripe:SetAllPoints()
    row.Stripe:SetAtlas("auctionhouse-rowstripe-1")

    row:SetHighlightAtlas("auctionhouse-ui-row-highlight", "ADD")

    row.Icon = row:CreateTexture(nil, "ARTWORK")
    row.Icon:SetSize(32, 32)
    row.Icon:SetPoint("LEFT", 6, 0)

    row.Name = row:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    row.Name:SetPoint("TOPLEFT", row.Icon, "TOPRIGHT", 8, -2)
    row.Name:SetPoint("RIGHT", row, "RIGHT", -NAME_RIGHT, 0)
    row.Name:SetJustifyH("LEFT")
    row.Name:SetWordWrap(false)

    row.Detail = row:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    row.Detail:SetPoint("TOPLEFT", row.Name, "BOTTOMLEFT", 0, -4)
    row.Detail:SetPoint("RIGHT", row, "RIGHT", -NAME_RIGHT, 0)
    row.Detail:SetJustifyH("LEFT")
    row.Detail:SetWordWrap(false)
    row.Detail:SetTextColor(unpack(Theme.MUTED))

    row.Price = row:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    row.Price:SetPoint("TOPRIGHT", row, "TOPRIGHT", -PRICE_RIGHT, -8)
    row.Price:SetJustifyH("RIGHT")

    row.Listed = row:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    row.Listed:SetPoint("TOPRIGHT", row.Price, "BOTTOMRIGHT", 0, -4)
    row.Listed:SetJustifyH("RIGHT")
    row.Listed:SetTextColor(unpack(Theme.MUTED))

    row.Verb = row:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    row.Verb:SetPoint("RIGHT", row, "RIGHT", -VERDICT_RIGHT, 0)
    row.Verb:SetJustifyH("RIGHT")

    -- Small, so it reads as part of the row and not a second heading.
    row.Tree = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
    row.Tree:SetSize(TREE_WIDTH, 20)
    row.Tree:SetPoint("RIGHT", -TREE_RIGHT, 0)
    row.Tree:SetNormalFontObject("GameFontNormalSmall")
    row.Tree:SetHighlightFontObject("GameFontHighlightSmall")
    row.Tree:SetText("Crafting tree")
    row.Tree:SetScript("OnClick", function(self)
        ns.ShowCraftTree(self:GetParent():GetElementData().itemID)
    end)
    row.Tree:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText("Crafting tree")
        GameTooltip:AddLine(
            "What it's made from and what it goes into, for your characters' recipes.",
            1,
            1,
            1,
            true
        )
        GameTooltip:Show()
    end)
    row.Tree:SetScript("OnLeave", GameTooltip_Hide)

    -- Left-click for the price history, right-click for the menu every
    -- item in the window has. Shift-click links it in chat, as it would
    -- anywhere else in the game.
    row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    row:SetScript("OnClick", function(self, mouseButton)
        local data = self:GetElementData()
        local link = LinkOf(data)
        if mouseButton == "RightButton" then
            ns.ItemMenu.Open(self, data.itemID, link)
            return
        end

        local insert = ChatFrameUtil and ChatFrameUtil.InsertLink or ChatEdit_InsertLink
        if IsShiftKeyDown() and link and insert then
            insert(link)
        else
            ns.ShowItemHistory(data.itemID, link)
        end
    end)

    row:SetScript("OnEnter", function(self)
        local data = self:GetElementData()
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        if data.link then
            GameTooltip:SetHyperlink(data.link)
        else
            GameTooltip:SetItemByID(data.itemID)
        end
        GameTooltip:Show()
    end)
    row:SetScript("OnLeave", GameTooltip_Hide)
end

local function FillRow(row, data, cache)
    local itemID = data.itemID
    local described = Describe(data, cache)

    row.Stripe:SetShown(row:GetOrderIndex() % 2 == 0)
    row.Icon:SetTexture(C_Item.GetItemIconByID(itemID))

    -- The client's own name when it has one, which also asks for the item
    -- if it hasn't: the quality colour comes with it, and the window
    -- redraws when it arrives. Until then, the name as last written down.
    local name = ns.ItemName(itemID) or data.name or ("Item " .. itemID)
    name = Theme.ItemName(name, C_Item.GetItemQualityByID(itemID))
    local count = ns.Bags.Counts()[itemID]
    if count then
        name = name .. "  " .. Theme.Aside(("x%d in your bags"):format(count))
    end
    row.Name:SetText(name)
    row.Detail:SetText(DetailText(described))

    if described.price then
        row.Price:SetText(Theme.Coins(described.price))
        row.Listed:SetText(Theme.Listed(described.listed))
    else
        row.Price:SetText("")
        row.Listed:SetText("")
    end

    if described.hasVerdict then
        local verb = described.advice.verb
        row.Verb:SetText(Theme.VERB_LABELS[verb])
        row.Verb:SetTextColor(unpack(Theme.VERB_COLORS[verb]))
    else
        row.Verb:SetText("")
    end
end

-- Links shift-clicked into the box --------------------------------------------

-- The tab whose box takes links. There's only ever one.
local current

-- When a link last went into the box, as GetTime counts. See the stack
-- splitter, below.
local tookLinkAt

-- The game puts a shift-clicked link into whichever box has the keyboard
-- through ChatFrameUtil.InsertLink, but only the boxes it knows about:
-- chat, macros, the professions search. Every other box has to watch it go
-- by and take the link itself. Hooked, not replaced, so the clicks that go
-- through it stay the game's own.
local function TakeLink(link)
    if not current or type(link) ~= "string" then
        return
    end
    local box = current.SearchBox
    if not box:IsVisible() or not box:HasFocus() then
        return
    end

    local itemID = tonumber(link:match("|Hitem:(%d+)"))
    if itemID then
        tookLinkAt = GetTime()
        current:ShowLink(itemID, link)
    end
end

if ChatFrameUtil and ChatFrameUtil.InsertLink then
    -- The older name, kept by Blizzard's deprecated-functions addon, holds
    -- the same function but in a slot of its own, so hooking one doesn't
    -- hook the other. Anything still calling the older name would go
    -- round us, so it's hooked too. Each call goes through one of the two,
    -- never both, so the box isn't handed the link twice.
    hooksecurefunc(ChatFrameUtil, "InsertLink", TakeLink)
    if type(ChatEdit_InsertLink) == "function" then
        hooksecurefunc("ChatEdit_InsertLink", TakeLink)
    end
elseif ChatEdit_InsertLink then
    hooksecurefunc("ChatEdit_InsertLink", TakeLink)
end

-- Shift-clicking a stack in the bags offers to split it whenever nothing
-- has said it took the link, and a hook can't say so. The box did take
-- it, so the offer is put away again the moment it opens.
if StackSplitFrame and StackSplitFrame.OpenStackSplitFrame then
    hooksecurefunc(StackSplitFrame, "OpenStackSplitFrame", function(self)
        if tookLinkAt == GetTime() then
            self:Hide()
        end
    end)
end

-- The tab ---------------------------------------------------------------------

--- Creates the Items tab. It starts hidden and fills its parent.
---@param parent table  frame to fill
---@return table tab    with :Refresh() and :Find(text)
function ItemsTab.Create(parent)
    local tab = CreateFrame("Frame", nil, parent)
    tab:SetAllPoints()
    tab:Hide()
    current = tab

    local heading = tab:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    heading:SetPoint("TOPLEFT", 12, -10)
    heading:SetText("Items")

    local about = tab:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    about:SetPoint("LEFT", heading, "RIGHT", 10, 0)
    about:SetTextColor(unpack(Theme.MUTED))
    about:SetText("Find any item for its price history and crafting tree")

    local box = CreateFrame("EditBox", nil, tab, "SearchBoxTemplate")
    box:SetSize(240, 20)
    box:SetPoint("TOPRIGHT", -24, -6)
    box:SetMaxLetters(60)
    box.Instructions:SetText("Item name")
    tab.SearchBox = box

    local empty = tab:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    empty:SetPoint("CENTER")
    empty:SetWidth(560)
    empty:SetTextColor(unpack(Theme.MUTED))

    local scrollBox = CreateFrame("Frame", nil, tab, "WowScrollBoxList")
    scrollBox:SetPoint("TOPLEFT", 6, -32)
    scrollBox:SetPoint("BOTTOMRIGHT", -22, 6)

    local scrollBar = CreateFrame("EventFrame", nil, tab, "MinimalScrollBar")
    scrollBar:SetPoint("TOPLEFT", scrollBox, "TOPRIGHT", 6, 0)
    scrollBar:SetPoint("BOTTOMLEFT", scrollBox, "BOTTOMRIGHT", 6, 0)

    -- Prices and verdicts of the rows drawn since the last rebuild.
    local described = {}

    local view = CreateScrollBoxListLinearView()
    view:SetElementExtent(ROW_HEIGHT)
    view:SetElementInitializer("Button", function(row, data)
        if not row.created then
            CreateRowWidgets(row)
        end
        FillRow(row, data, described)
    end)
    ScrollUtil.InitScrollBoxListWithScrollBar(scrollBox, scrollBar, view)

    -- One item shown first whatever the search finds: the one shift-
    -- clicked in, or asked for by number. { itemID, link }
    local pinned

    -- What the list was last built for, so a redraw for new prices keeps
    -- its place and a new search starts at the top.
    local lastText

    -- The window takes its footer from the tab, so it has to be the one
    -- to redraw. Typing waits for a pause first.
    local typedAt
    local function SearchSoon()
        local at = GetTime()
        typedAt = at
        C_Timer.After(TYPING_PAUSE, function()
            if typedAt == at then
                ns.Publish("COURSE_CHANGED")
            end
        end)
    end

    box:HookScript("OnTextChanged", function(self, userInput)
        -- Typing over a shift-clicked item lets it go, and so does
        -- clearing the box, which the clear button does without typing.
        local text = strtrim(self:GetText())
        if pinned and (text == "" or (userInput and text ~= pinned.name)) then
            pinned = nil
        end
        SearchSoon()
    end)

    --- Puts an item in the box: its name, with the item itself listed
    --- first, though other things share the name.
    ---@param itemID number
    ---@param link string|nil
    function tab:ShowLink(itemID, link)
        local name = link and link:match("|h%[(.-)%]|h") or ns.ItemName(itemID)
        ns.Names.Note(itemID, name)
        pinned = { itemID = itemID, link = link, name = name }
        -- Without a name, the number finds it just as well.
        box:SetText(name or tostring(itemID))
        box:SetCursorPosition(0)
    end

    --- Searches for something, as typed into the box or after /gw find.
    --- A link searches for that item.
    ---@param text string
    function tab:Find(text)
        text = strtrim(text or "")
        local itemID = tonumber(text:match("|Hitem:(%d+)"))
        if itemID then
            self:ShowLink(itemID, text:match("|c.-|h|r") or text)
        else
            pinned = nil
            box:SetText(text)
        end
        ns.Publish("COURSE_CHANGED")
    end

    -- The pinned item, or the one a number names if it's a real item.
    local function PinnedRow(text)
        if pinned then
            return { itemID = pinned.itemID, link = pinned.link, name = pinned.name }
        end
        local number = tonumber(text:match("^%d+$"))
        if number and C_Item.GetItemInfoInstant(number) then
            return { itemID = number, name = ns.Names.Get(number) }
        end
    end

    --- Searches again with what's in the box.
    ---@return string footer  a line about what's on show, for the window
    function tab:Refresh()
        local text = strtrim(box:GetText())
        described = {}

        local rows = {}
        local first = PinnedRow(text)
        if first then
            table.insert(rows, first)
        end

        local total = 0
        if #text >= SHORTEST then
            local matches
            matches, total = ns.Names.Search(text, MOST_ROWS)
            for _, match in ipairs(matches) do
                if not first or match.itemID ~= first.itemID then
                    table.insert(rows, match)
                end
            end
        end

        if text == "" then
            empty:SetText(NOTHING_TYPED)
        elseif #text < SHORTEST and not first then
            empty:SetText(TOO_SHORT)
        else
            empty:SetText(NO_MATCH)
        end
        empty:SetShown(#rows == 0)

        local samePlace = text == lastText
        lastText = text
        scrollBox:SetDataProvider(
            CreateDataProvider(rows),
            samePlace and ScrollBoxConstants.RetainScrollPosition
                or ScrollBoxConstants.DiscardScrollPosition
        )

        if total > MOST_ROWS then
            return ("Showing the first %d of %s. Type more of the name to narrow it down."):format(
                MOST_ROWS,
                FormatLargeNumber(total)
            )
        end
        return FOOTER
    end

    return tab
end
