local _, ns = ...

-- Goldwise's page in the game's own Options window.
--
-- Everything works without a visit here. These are for people who want to
-- change how it behaves.

-- Adds a tick box bound to one key of the saved settings.
local function AddCheckbox(category, key, label, tooltip)
    local setting = Settings.RegisterAddOnSetting(
        category,
        "Goldwise_" .. key,
        key,
        ns.settings,
        Settings.VarType.Boolean,
        label,
        ns.DEFAULT_SETTINGS[key]
    )
    Settings.CreateCheckbox(category, setting, tooltip)

    Settings.SetOnValueChangedCallback("Goldwise_" .. key, function()
        ns.Publish("SETTINGS_CHANGED")
    end)
end

-- Registered at login rather than when the addon loads, so the Options
-- window has finished setting itself up.
ns.OnEvent("PLAYER_LOGIN", function()
    local category = Settings.RegisterVerticalLayoutCategory("Goldwise")

    AddCheckbox(
        category,
        "autoScan",
        "Read prices when the auction house opens",
        "Takes about fifteen seconds and steps aside if you start searching. "
            .. "Skipped if prices were read in the last quarter of an hour."
    )

    AddCheckbox(
        category,
        "deepScan",
        "Read every auction when possible",
        "A fuller read that shows how many are listed at each price. "
            .. "The game allows it once every 15 minutes; otherwise the quick read is used."
    )

    AddCheckbox(
        category,
        "tooltipPrice",
        "Show auction prices on item tooltips",
        "One line with the lowest price and how many are listed. "
            .. "Left to Auctionator if you have that installed."
    )

    AddCheckbox(
        category,
        "tooltipChart",
        "Show a price chart under item tooltips",
        "A small two-week trend. Appears once an item has a few days of history."
    )

    AddCheckbox(
        category,
        "tooltipHeld",
        "Show how many your other characters hold",
        "Counts their bags as of their last login. Left to Bagnon if you have that installed."
    )

    AddCheckbox(
        category,
        "auditorMode",
        "Auditor mode",
        "The goblin delivers the same advice at full volume. The facts don't change."
    )

    Settings.RegisterAddOnCategory(category)
end)
