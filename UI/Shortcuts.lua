local _, ns = ...

-- The quick ways to an item's crafting tree and price history: a click
-- on the item with a key held down, and a key of the player's choosing.
--
-- Both borrow from a crowded place. Every key and every click with a key
-- held is something the game or another addon may already use, and a
-- shortcut that fights with one of those is worse than none. So this has
-- its own page in the options, under Goldwise, where each can be set,
-- and which says so when what's been chosen is already taken.

local Shortcuts = {}
ns.Shortcuts = Shortcuts

local Theme = ns.Theme

-- The click -------------------------------------------------------------------

-- The clicks on offer for the crafting tree, by the number saved in the
-- settings. All use the right button: a left click with a key held is
-- where the game keeps linking in chat and the dressing room, and where
-- bag addons keep their own tricks.
local CLICKS = {
    { label = "Alt + right-click", hint = "Alt-right-click", alt = true },
    { label = "Ctrl + right-click", hint = "Ctrl-right-click", ctrl = true },
    { label = "Ctrl + Alt + right-click", hint = "Ctrl-Alt-right-click", alt = true, ctrl = true },
}

-- What the game itself can be set to do on a click of an item with a key
-- held, under Options > Controls. Each is saved as the keys and button
-- that trigger it: "SHIFT-BUTTON1", or just "ALT" for either button.
local GAME_CLICKS = {
    CHATLINK = "linking the item in chat",
    DRESSUP = "the dressing room",
    SPLITSTACK = "splitting a stack",
    SOCKETITEM = "socketing",
    EXPANDITEM = "expanding the item",
    AUTOLOOTTOGGLE = "auto-loot",
    PICKUPITEM = "picking the item up",
}

local function ChosenClick()
    return ns.settings and CLICKS[ns.settings.treeClick]
end

--- How to say the click that opens the crafting tree: "Alt-right-click".
---@return string|nil hint  nil when the player has turned it off, or the
---        client can't tell us about clicks on items
function Shortcuts.TreeClickHint()
    local click = ChosenClick()
    return click and HandleModifiedItemClick and click.hint or nil
end

-- What else the chosen click is set to do, as a list of descriptions.
local function ClickClashes(click)
    local keys = (click.alt and "ALT" or "") .. (click.alt and click.ctrl and "-" or "")
    keys = keys .. (click.ctrl and "CTRL" or "")

    local clashes = {}
    for action, what in pairs(GAME_CLICKS) do
        -- Not every client has every one of these.
        local ok, set = pcall(GetModifiedClick, action)
        if ok and (set == keys or set == keys .. "-BUTTON2") then
            table.insert(clashes, what)
        end
    end
    table.sort(clashes)
    return clashes
end

-- The game sends every click made on an item with a key held down
-- through one function, wherever the item is: a bag, a chat link, the
-- auction house. We watch it go by. Kept to items that are part of
-- something the player can make, so the click does nothing new anywhere
-- else.
if HandleModifiedItemClick then
    hooksecurefunc("HandleModifiedItemClick", function(link)
        local click = ChosenClick()
        if not click or not link or GetMouseButtonClicked() ~= "RightButton" then
            return
        end

        local held = IsAltKeyDown() == (click.alt == true)
            and IsControlKeyDown() == (click.ctrl == true)
            and not IsShiftKeyDown()
        if not held then
            return
        end

        local itemID = C_Item.GetItemInfoInstant(link)
        if itemID and ns.CraftTree.Has(itemID) then
            ns.ShowCraftTree(itemID)
        end
    end)
end

-- The keys --------------------------------------------------------------------

-- The two things a key can be given to. The commands are declared in
-- Bindings.xml, so they're also in the game's own list of key bindings.
local KEYS = {
    {
        command = "GOLDWISE_TREE",
        label = "Crafting tree",
        about = "What the item under your mouse is made from, and what it goes into.",
    },
    {
        command = "GOLDWISE_HISTORY",
        label = "Price history",
        about = "The full price history of the item under your mouse.",
    },
}

-- Keys that only ever accompany another. Pressing one isn't a choice.
local HELD_KEYS = {
    LSHIFT = true,
    RSHIFT = true,
    LCTRL = true,
    RCTRL = true,
    LALT = true,
    RALT = true,
    LMETA = true,
    RMETA = true,
    UNKNOWN = true,
}

-- A key with whatever is held down alongside it, the way the game writes
-- bindings: "ALT-CTRL-T".
local function Chord(key)
    return (IsAltKeyDown() and "ALT-" or "")
        .. (IsControlKeyDown() and "CTRL-" or "")
        .. (IsShiftKeyDown() and "SHIFT-" or "")
        .. key
end

-- A key as the game shows it to players: "Alt-T".
local function KeyText(key)
    return GetBindingText and GetBindingText(key) or key
end

-- What a command is called in the game's key binding list.
local function CommandName(command)
    local name = GetBindingName and GetBindingName(command)
    return name and name ~= "" and name or command
end

-- Gives a key to one of our commands, taking it from whatever had it,
-- and takes away any key the command had before. One key each is plenty,
-- and it keeps what this page shows the whole truth.
local function Assign(command, key)
    for _, old in ipairs({ GetBindingKey(command) }) do
        SetBinding(old)
    end
    if key then
        SetBinding(key, command)
    end
    SaveBindings(GetCurrentBindingSet())
end

-- The page --------------------------------------------------------------------

local ROW_HEIGHT = 74
local BUTTON_WIDTH = 190

-- Where the first row starts, under the title and the introduction.
local FIRST_ROW_TOP = 86

local function CreateRow(page, top, label, about)
    local row = CreateFrame("Frame", nil, page)
    row:SetHeight(ROW_HEIGHT)
    row:SetPoint("TOPLEFT", 16, -top)
    row:SetPoint("RIGHT", -16, 0)

    row.Label = row:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    row.Label:SetPoint("TOPLEFT", 0, -4)
    row.Label:SetText(label)

    row.About = row:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    row.About:SetPoint("TOPLEFT", row.Label, "BOTTOMLEFT", 0, -4)
    row.About:SetPoint("RIGHT", -(BUTTON_WIDTH + 16), 0)
    row.About:SetJustifyH("LEFT")
    row.About:SetTextColor(unpack(Theme.MUTED))
    row.About:SetText(about)

    row.Button = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
    row.Button:SetSize(BUTTON_WIDTH, 24)
    row.Button:SetPoint("TOPRIGHT", 0, -2)

    -- Where a clash is spelled out, under everything else in the row.
    row.Status = row:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    row.Status:SetPoint("TOPLEFT", row.About, "BOTTOMLEFT", 0, -6)
    row.Status:SetPoint("RIGHT", 0, 0)
    row.Status:SetJustifyH("LEFT")

    function row:Say(text, isWarning)
        self.Status:SetText(text or "")
        self.Status:SetTextColor(unpack(isWarning and Theme.SPENDING or Theme.MUTED))
    end

    return row
end

local function CreatePage()
    -- Hidden until the options show it. A frame with no parent counts as
    -- on screen from the moment it's made, and this one has buttons that
    -- can take the keyboard.
    local page = CreateFrame("Frame")
    page:Hide()

    local title = page:CreateFontString(nil, "ARTWORK", "GameFontHighlightHuge")
    title:SetPoint("TOPLEFT", 16, -16)
    title:SetText("Goldwise shortcuts")

    local intro = page:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    intro:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -10)
    intro:SetPoint("RIGHT", -16, 0)
    intro:SetJustifyH("LEFT")
    intro:SetText(
        "Quick ways to an item's crafting tree and price history. None of them is "
            .. "needed: both pages can be reached from Goldwise's own window."
    )

    -- The row whose button is waiting for a key, and the key it was
    -- offered that something else already has.
    local listening, contested

    local Refresh

    local function StopListening()
        listening, contested = nil, nil
        Refresh()
    end

    -- The click.
    local clickRow = CreateRow(
        page,
        FIRST_ROW_TOP,
        "Crafting tree, with a click",
        "On an item in your bags, in chat or at the auction house."
    )
    clickRow.Button:SetScript("OnClick", function(self)
        MenuUtil.CreateContextMenu(self, function(_, root)
            local function IsChosen(index)
                return ns.settings.treeClick == index
            end
            local function Choose(index)
                ns.settings.treeClick = index
                ns.Publish("SETTINGS_CHANGED")
                Refresh()
            end

            for index, click in ipairs(CLICKS) do
                root:CreateRadio(click.label, IsChosen, Choose, index)
            end
            root:CreateRadio("No click", IsChosen, Choose, 0)
        end)
    end)

    -- The keys.
    local keyRows = {}
    for index, key in ipairs(KEYS) do
        local row = CreateRow(
            page,
            FIRST_ROW_TOP + index * ROW_HEIGHT,
            key.label .. ", with a key",
            key.about
        )
        row.command = key.command
        keyRows[index] = row

        row.Button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        row.Button:SetScript("OnClick", function(_, mouseButton)
            if InCombatLockdown() then
                row:Say("Keys can't be changed in combat. Try again in a moment.", true)
                return
            end

            contested = nil
            if mouseButton == "RightButton" then
                listening = nil
                Assign(row.command, nil)
            else
                -- A second click on a button that's waiting calls it off.
                listening = listening ~= row and row or nil
            end
            Refresh()
        end)

        -- What the button does with a key while it's waiting for one.
        -- It's only given this, and the keyboard, for as long as it is
        -- waiting: a button with a key handler takes every key pressed,
        -- anywhere in the game, whether it wants it or not.
        function row.OnKey(_, pressed)
            if listening ~= row or HELD_KEYS[pressed] then
                return
            end

            if pressed == "ESCAPE" then
                StopListening()
                return
            end

            if InCombatLockdown() then
                StopListening()
                row:Say("Keys can't be changed in combat. Try again in a moment.", true)
                return
            end

            -- A key that already does something is only taken on a
            -- second press, once the player has been told what it does.
            local chord = Chord(pressed)
            local holder = GetBindingAction(chord, true)
            local taken = holder and holder ~= "" and holder ~= row.command
            if taken and contested ~= chord then
                contested = chord
                Refresh()
                return
            end

            Assign(row.command, chord)
            StopListening()
        end
    end

    local footnote = page:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    footnote:SetPoint("TOPLEFT", 16, -(FIRST_ROW_TOP + (#KEYS + 1) * ROW_HEIGHT + 8))
    footnote:SetPoint("RIGHT", -16, 0)
    footnote:SetJustifyH("LEFT")
    footnote:SetTextColor(unpack(Theme.MUTED))
    footnote:SetText(
        "To set a key, click its button and press the key, with Alt, Ctrl or Shift "
            .. "held if you like. Right-click the button to clear it. The same keys "
            .. "are listed under Options, Keybindings, Goldwise."
    )

    function Refresh()
        local click = ChosenClick()
        clickRow.Button:SetText(click and click.label or "No click")
        if not HandleModifiedItemClick then
            clickRow:Say(
                "This version of the game doesn't tell addons about clicks on items.",
                true
            )
        elseif not click then
            clickRow:Say("Off. The key below and Goldwise's own window still open the tree.")
        else
            local clashes = ClickClashes(click)
            if #clashes > 0 then
                clickRow:Say(
                    ("The game is also set to use this click for %s, so both will happen. "):format(
                        table.concat(clashes, " and ")
                    )
                        .. "Pick another here, or change the game's under Options, Controls.",
                    true
                )
            else
                clickRow:Say("Nothing in the game's own click settings uses this.")
            end
        end

        for _, row in ipairs(keyRows) do
            local key = GetBindingKey(row.command)
            local waiting = listening == row

            -- Only the button that's waiting takes keys, and while it is,
            -- it keeps them to itself. The rest of the time it has no
            -- handler and no keyboard, and keys go on to the game.
            row.Button:SetScript("OnKeyDown", waiting and row.OnKey or nil)
            row.Button:EnableKeyboard(waiting)

            if waiting and contested then
                row.Button:SetText(KeyText(contested))
                row:Say(
                    ("%s is already used for %s. Press it again to use it here instead, "):format(
                        KeyText(contested),
                        CommandName(GetBindingAction(contested, true))
                    )
                        .. "press another key, or Escape to leave things as they are.",
                    true
                )
            elseif waiting then
                row.Button:SetText("Press a key...")
                row:Say("Waiting for a key. Escape leaves it as it is.")
            elseif not key then
                row.Button:SetText("No key")
                row:Say("")
            else
                row.Button:SetText(KeyText(key))

                -- A key can be ours in the list and still be answered by
                -- something else: an addon can take a key over while its
                -- own window is up.
                local holder = GetBindingAction(key, true)
                if holder ~= row.command then
                    row:Say(
                        ("Something else is answering %s just now: %s."):format(
                            KeyText(key),
                            CommandName(holder)
                        ),
                        true
                    )
                else
                    row:Say("")
                end
            end
        end
    end

    -- The options call this each time they put the page up, including
    -- the times the page doesn't hear that it has been shown.
    page.OnRefresh = StopListening
    page:SetScript("OnShow", StopListening)
    -- Never leave a button swallowing keys behind a closed window.
    page:SetScript("OnHide", StopListening)

    -- Bindings changed somewhere else: the game's own list, or a profile.
    ns.OnEvent("UPDATE_BINDINGS", function()
        if page:IsVisible() then
            Refresh()
        end
    end)

    -- A fight has started. A button left waiting would eat the first
    -- ability the player reached for.
    ns.OnEvent("PLAYER_REGEN_DISABLED", function()
        if listening then
            StopListening()
        end
    end)

    return page
end

--- Adds the shortcuts page beneath Goldwise's in the game's Options.
---@param category table  Goldwise's own options page
function Shortcuts.Register(category)
    -- An older client without this kind of page still has the keys in
    -- its own binding list, and the click at its default.
    if Settings.RegisterCanvasLayoutSubcategory then
        Settings.RegisterCanvasLayoutSubcategory(category, CreatePage(), "Shortcuts")
    end
end
