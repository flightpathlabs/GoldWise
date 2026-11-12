local addonName, ns = ...

-- The About tab: what Goldwise is, how it decides, where its numbers come
-- from, and the small print. One scrolling page of text.

local AboutTab = {}
ns.AboutTab = AboutTab

local TEXT_WIDTH = 700

-- Headings are wrapped in the game's title yellow.
local function Heading(text)
    return "|cffffd100" .. text .. "|r"
end

local function PageText()
    local version = C_AddOns.GetAddOnMetadata(addonName, "Version") or "?"

    return table.concat({
        Heading("Goldwise " .. version),
        "A clear guide to buying and selling. It keeps a price history for what you "
            .. "carry and tells you, in a sentence, what's worth doing with it.",
        "It watches and advises. It never posts, buys or cancels anything for you.",
        "",
        Heading("Opening it"),
        "Type /gw or /goldwise, or left-click the minimap button. Right-click the "
            .. "button for options.",
        "/gw goal 50 sets a 50 gold savings target on the Purse tab. /gw goal off clears it.",
        "",
        Heading("The tabs"),
        "Assets: what's in your bags, or on all your characters, with the lowest "
            .. "price, a two-week trend and a verdict. Click a row for its price history.",
        "Prospects: what you could gather at your level and with your professions, "
            .. "by what each one sells for today, and where to do it.",
        "Purse: what you have, what comes in and goes out, and what's about to cost you.",
        "Places: the nearest trainer for your class and each profession, and the "
            .. "nearest auction house, repairer, bank, flight master and inn, each "
            .. "with a button that puts it on your map.",
        "",
        Heading("How it decides"),
        "Sell, if it clears more than a vendor pays by at least the listing deposit.",
        "Vendor, if it's worth no more than the deposit, or a vendor pays as much.",
        "Hold, if it's well below its usual price. Usual needs four days of history; "
            .. "until then Goldwise says so instead of guessing.",
        "Proceeds are what's left after the auction house takes its cut.",
        "",
        Heading("Where prices come from"),
        "Your own visits. Goldwise reads the auction house when you open it and "
            .. "steps aside if you start a search. These are kept for months.",
        "Other Goldwise players. Whoever was at the auction house last keeps "
            .. "everyone's prices fresh, over a hidden chat channel. Only prices are "
            .. "exchanged. You can turn this off in the options.",
        "Goldwise Prices, if you have it installed: the last thirty days for every "
            .. "auction house, so a new character isn't starting from nothing. "
            .. "That data comes from "
            .. ns.Feed.SOURCE
            .. ".",
        "Every price can tell you how old it is and which of these it came from.",
        "",
        Heading("Auditor mode"),
        "An option. The goblin delivers the same advice at full volume. The facts "
            .. "don't change, only the tone.",
        "",
        Heading("Thanks"),
        "Class training prices come from What's Training? by Sveng, used under its "
            .. "MIT licence. If you have that addon installed, Goldwise asks it directly.",
        "",
        Heading("The small print"),
        "Goldwise is a free, fan-made addon from Flight Path Labs. Its goblin mascot "
            .. "is an original cartoon character and the branding is a joke. Any "
            .. "resemblance to real people, shows, apps or companies is parody, and "
            .. "Goldwise is not affiliated with, endorsed by or sponsored by any of them.",
        "It offers advice about a video game's auction house and nothing else. None "
            .. "of it is financial advice.",
        "World of Warcraft and related names and artwork are trademarks of Blizzard "
            .. "Entertainment. This project is not affiliated with or endorsed by "
            .. "Blizzard Entertainment.",
    }, "\n\n")
end

--- Creates the About tab. It starts hidden and fills its parent.
---@param parent table  frame to fill
---@return table tab
function AboutTab.Create(parent)
    local tab = CreateFrame("Frame", nil, parent)
    tab:SetAllPoints()
    tab:Hide()

    -- The template brings its own scroll bar.
    local scroll = CreateFrame("ScrollFrame", nil, tab, "ScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 16, -14)
    scroll:SetPoint("BOTTOMRIGHT", -30, 12)

    local content = CreateFrame("Frame", nil, scroll)
    content:SetSize(TEXT_WIDTH, 1)
    scroll:SetScrollChild(content)

    local text = content:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    text:SetPoint("TOPLEFT")
    text:SetWidth(TEXT_WIDTH)
    text:SetJustifyH("LEFT")
    text:SetSpacing(3)
    text:SetText(PageText())

    -- The scroll range comes from the child's height, which has to be
    -- set by hand once the text has been laid out.
    content:SetHeight(text:GetStringHeight())

    return tab
end
