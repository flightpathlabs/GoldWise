-- Luacheck configuration for Goldwise.
-- Run from the repo root:  luacheck .
--
-- There is no maintained luacheck "std" for the 12.x / Forever API, so we
-- list the globals we actually touch. Add to read_globals as new API gets
-- used; a typo in an API name then shows up as a lint warning instead of a
-- nil error in game.

std = "lua51"
max_line_length = 100
max_string_line_length = false
max_comment_line_length = 100
codes = true

exclude_files = {
    "Libs/**",
    ".release/**",
}

ignore = {
    "212/self", -- unused "self" on mixin methods is normal
    "212/event", -- event handlers often ignore the event name
}

-- The only globals Goldwise creates: its saved data, slash command and
-- the addon-list click handler named in the TOC.
globals = {
    "SlashCmdList",
    "UISpecialFrames",

    -- Ours
    "GoldwiseDB",
    "SLASH_GOLDWISE1",
    "SLASH_GOLDWISE2",
    "Goldwise_OnAddonCompartmentClick",
}

read_globals = {
    -- The companion prices addon, when installed
    "GoldwisePricesData",
    "GoldwisePricesIndex",

    -- Lua extensions the client adds
    "strsplit",
    "strtrim",
    "tinsert",
    "tremove",
    "wipe",
    "format",
    "date",
    "time",
    "CopyTable",
    "Mixin",
    "CreateFromMixins",

    -- Client constants
    "WOW_PROJECT_ID",
    "WOW_PROJECT_CAMELOT",
    "Enum",
    "BACKPACK_CONTAINER",
    "NUM_BAG_SLOTS",
    "INVSLOT_FIRST_EQUIPPED",
    "INVSLOT_LAST_EQUIPPED",
    "SOUNDKIT",
    "NUM_TOTAL_EQUIPPED_BAG_SLOTS",

    -- Blizzard's shared Lua helpers
    "ColorManager",
    "CreateDataProvider",
    "CreateScrollBoxListLinearView",
    "FormatLargeNumber",
    "GameTooltip_Hide",
    "GetMoneyString",
    "OpenWorldMap",
    "PanelTemplates_SetNumTabs",
    "PanelTemplates_SetTab",
    "PanelTemplates_TabResize",
    "ScrollBoxConstants",
    "ScrollUtil",
    "UiMapPoint",
    "CreateVector2D",
    "BuyTrainerService",

    -- Frames and widgets
    "CreateFrame",
    "UIParent",
    "GameTooltip",
    "Minimap",
    "ItemRefTooltip",
    "Settings",
    "TooltipDataProcessor",

    -- Namespaced API
    "C_AddOns",
    "C_AuctionHouse",
    "C_Container",
    "C_Item",
    "C_Timer",
    "C_TradeSkillUI",
    "C_ChatInfo",
    "C_Map",
    "C_GameRules",
    "C_SuperTrack",
    "C_Trainer",

    -- Loose API functions
    "GetBuildInfo",
    "GetTime",
    "GetServerTime",
    "GetMoney",
    "UnitName",
    "UnitClass",
    "UnitLevel",
    "UnitFactionGroup",
    "geterrorhandler",
    "GetProfessionInfo",
    "GetProfessions",
    "CanMerchantRepair",
    "GetInventoryItemDurability",
    "GetNumTrainerServices",
    "GetRepairAllCost",
    "GetTrainerServiceCost",
    "GetTrainerServiceInfo",
    "GetTrainerServiceStepIndex",
    "IsTradeskillTrainer",
    "PlaySound",
    "IsInInstance",
    "RemoveChatWindowChannel",
    "NUM_CHAT_WINDOWS",
    "GetCursorPosition",
    "GetMinimapShape",
    "InCombatLockdown",
    "GetRealmName",
    "GetNormalizedRealmName",
    "GetCurrentRegion",
    "GetCurrentRegionName",
    "RegionalUniqueNamesEnabled",
    "GetRealZoneText",
    "GetSubZoneText",
    "IsResting",
    "ReloadUI",
    "hooksecurefunc",
    "issecretvalue",
    "ItemLocation",
    "GetChannelName",
    "JoinTemporaryChannel",
    "LeaveChannelByName",
    "ButtonFrameTemplate_HidePortrait",

    -- Libraries
    "LibStub",

    -- The client adds a few functions to the standard table library
    table = { fields = { "wipe" } },
}
