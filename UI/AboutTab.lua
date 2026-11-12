local addonName, ns = ...

-- The About tab: the goblin in full, what Goldwise is, how to get the most
-- from it, how it decides, where its numbers come from, and the small
-- print. One scrolling page, set out in sections.

local AboutTab = {}
ns.AboutTab = AboutTab

local Theme = ns.Theme

local PAGE_WIDTH = 700

-- The picture at the top, and the gap between it and the words beside it.
local SCENE_SIZE = 250
local SCENE_GAP = 20

-- Space above a section's heading, and between the things inside it.
local SECTION_GAP = 22
local LINE_GAP = 8

-- Where each line of a list starts, leaving room for its marker.
local LIST_INDENT = 20

-- What the page says -----------------------------------------------------------------

-- Each section is a heading and what goes under it: `intro` paragraphs,
-- then a `list` of short points, each with a marker, then `text`
-- paragraphs to close. Any of the three can be left out.
local function Sections()
    return {
        {
            heading = "It gets sharper the more you play",
            intro = {
                "Goldwise starts out knowing nothing and learns from what your own game "
                    .. "sees. There's nothing to set up. Play as you normally would, and "
                    .. "stop by an auction house when you're in town.",
            },
            list = {
                "Your first visit: it knows what everything costs today, and what in your "
                    .. "bags is worth selling.",
                "After visits on four different days: charts fill in, and it can tell a good "
                    .. "price from a poor one, so it starts saying when to hold.",
                "Every visit after that: the history gets longer and the advice steadier.",
                "Along the way it remembers the trainers, repairers, banks and flight masters "
                    .. "you use, so Places fills in too.",
            },
        },
        {
            heading = "Quick tips",
            list = {
                "Open any auction house and let it read. The panel on top of the window "
                    .. "says when it's done and what your bags would sell for.",
                "Check Assets before you sell to a merchant. Anything marked Sell is "
                    .. "worth the walk to the auction house.",
                "Using something, not selling it? Right-click it on Assets and choose Keep. "
                    .. "Goldwise stops suggesting you sell it. Fishing poles and profession "
                    .. "tools are kept from the start.",
                "Rest your mouse on any item, anywhere, for its price and a small chart "
                    .. "of how it's moved.",
                "For the full history of anything you can point at, type /gw history, or "
                    .. "give it a key under Options, Keybindings, Goldwise. You can also "
                    .. "shift-click an item after typing /gw and a space.",
                "In your bags and bank, a gold rim and a coin mark what's worth taking to "
                    .. "the auction house.",
                "On Purse, press Where beside a line of training to see which city's "
                    .. "trainers are cheapest for you, and put them on your map.",
                "Lost? Places lists the nearest trainer, repairer, bank and flight master, "
                    .. "each with a Map button.",
                "Some vendors sell recipes that fetch far more at auction, and most players "
                    .. 'never find them. On Prospects, press "I want to..." and choose '
                    .. '"Buy from vendors, sell at auction" for the list, with the profit '
                    .. "worked out.",
                "Ore or bars? Cloth or bolts? Open each profession window once so Goldwise "
                    .. 'can read your recipes, then choose "Turn what I have into more" '
                    .. 'under "I want to..." on Prospects. It compares making a thing with '
                    .. "selling what goes into it.",
                "Saving for a mount? /gw goal 50 tracks a 50 gold target on the Purse tab.",
                "Right-click the minimap button for options, Auditor mode among them.",
            },
        },
        {
            heading = "The tabs",
            list = {
                "Assets: what's in your bags, or on all your characters, with the lowest "
                    .. "price, a two-week trend and a verdict. Click a row for its history.",
                "Prospects: what you could gather at your level and with your professions, "
                    .. 'by what each one sells for today. Or press "I want to..." and pick '
                    .. "a zone, and it plans the trip: what to see to before you leave, "
                    .. "what to gather and buy while you're there, and who's on the spot.",
                "Purse: what you have, a chart of what's come in and gone out each day "
                    .. "for the last month, and what's about to cost you: repairs, training, "
                    .. "and whatever you're saving for.",
                "Places: the nearest trainer for your class and each profession, and the "
                    .. "nearest auction house, repairer, bank, flight master and inn.",
                "Recipes: what vendors sell that you haven't learned, for the professions "
                    .. "you have, where to buy each, and what the tradeable ones fetch at "
                    .. "auction. Goldwise also tells you when one is on sale where you are.",
            },
        },
        {
            heading = "How it decides",
            list = {
                "Sell, if it clears more than a vendor pays by at least the listing deposit.",
                "Vendor, if it's worth no more than the deposit, or a vendor pays as much.",
                "Hold, if it's well below its usual price. Usual needs four days of history; "
                    .. "until then Goldwise says so instead of guessing.",
            },
            text = { "Proceeds are what's left after the auction house takes its cut." },
        },
        {
            heading = "Where prices come from",
            list = {
                "Your own visits. Goldwise reads the auction house when you open it, and "
                    .. "reads along when you or another addon searches. These are kept for "
                    .. "three months, or as long as you choose in the options.",
                "Other Goldwise players. Whoever was at the auction house last keeps "
                    .. "everyone's prices fresh, over a hidden chat channel. Only prices are "
                    .. "exchanged, and you can turn it off in the options.",
            },
            text = { "Every price can tell you how old it is and which of these it came from." },
        },
        {
            heading = "Auditor mode",
            text = {
                "An option. The goblin delivers the same advice at full volume. The facts "
                    .. "don't change, only the tone.",
            },
        },
        {
            heading = "Thanks",
            text = {
                "Class training prices, and the list of which vendors sell which recipes, "
                    .. "come from What's Training? by Sveng, used under its MIT licence. If "
                    .. "you have that addon installed, Goldwise asks it for training directly.",
            },
        },
        {
            heading = "The small print",
            text = {
                "Goldwise is a free, fan-made addon from Flight Path Labs. Its goblin mascot "
                    .. "is an original cartoon character and the branding is a joke. Any "
                    .. "resemblance to real people, shows, apps or companies is parody, and "
                    .. "Goldwise is not affiliated with, endorsed by or sponsored by any of them.",
                "It offers advice about a video game's auction house and nothing else. None "
                    .. "of it is financial advice.",
                "World of Warcraft and related names and artwork are trademarks of Blizzard "
                    .. "Entertainment. This project is not affiliated with or endorsed by "
                    .. "Blizzard Entertainment.",
            },
        },
    }
end

-- Building the page ------------------------------------------------------------------

-- The page is a stack of pieces, each placed under the one before. Every
-- piece is given its width outright, because its height depends on how
-- its text wraps, and that isn't known until the width is.
--
-- `blocks` collects them as { region, x, gap, extra }: how far in the
-- piece sits, the space above it, and anything that hangs off it.

local function AddText(content, blocks, font, text, x, gap)
    local line = content:CreateFontString(nil, "ARTWORK", font)
    line:SetWidth(PAGE_WIDTH - x)
    line:SetJustifyH("LEFT")
    line:SetSpacing(3)
    line:SetText(text)

    table.insert(blocks, { region = line, x = x, gap = gap })
    return line
end

local function AddHeading(content, blocks, text)
    local heading = AddText(content, blocks, "GameFontNormalLarge", text, 0, SECTION_GAP)

    -- A thin rule under the heading, the way the game's own panels divide
    -- themselves up.
    local rule = content:CreateTexture(nil, "ARTWORK")
    rule:SetHeight(1)
    rule:SetPoint("TOPLEFT", heading, "BOTTOMLEFT", 0, -4)
    rule:SetWidth(PAGE_WIDTH)
    rule:SetColorTexture(Theme.COIN[1], Theme.COIN[2], Theme.COIN[3], 0.35)
end

local function AddListItem(content, blocks, text, first)
    -- A little more room under a heading, to clear its rule.
    local line =
        AddText(content, blocks, "GameFontHighlight", text, LIST_INDENT, first and 14 or LINE_GAP)

    local marker = content:CreateTexture(nil, "ARTWORK")
    marker:SetSize(14, 14)
    marker:SetPoint("TOPRIGHT", line, "TOPLEFT", -4, 1)
    marker:SetTexture("Interface\\QuestFrame\\UI-Quest-BulletPoint")
end

-- The top of the page: the picture, with the name and a few words beside it.
local function AddMasthead(content)
    -- A dark mount behind the picture gives it an edge against the panel.
    local mount = content:CreateTexture(nil, "BACKGROUND")
    mount:SetSize(SCENE_SIZE + 4, SCENE_SIZE + 4)
    mount:SetPoint("TOPLEFT")
    mount:SetColorTexture(0, 0, 0, 0.8)

    local scene = content:CreateTexture(nil, "ARTWORK")
    scene:SetSize(SCENE_SIZE, SCENE_SIZE)
    scene:SetPoint("CENTER", mount)
    scene:SetTexture(Theme.SCENE)

    local textLeft = SCENE_SIZE + 4 + SCENE_GAP
    local textWidth = PAGE_WIDTH - textLeft

    local name = content:CreateFontString(nil, "ARTWORK", "GameFontNormalHuge")
    name:SetPoint("TOPLEFT", textLeft, -6)
    name:SetText("Goldwise")

    local version = content:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    version:SetPoint("BOTTOMLEFT", name, "BOTTOMRIGHT", 8, 3)
    version:SetText("version " .. (C_AddOns.GetAddOnMetadata(addonName, "Version") or "?"))

    local tagline = content:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    tagline:SetPoint("TOPLEFT", name, "BOTTOMLEFT", 0, -4)
    tagline:SetText("Auction House Guide")
    tagline:SetTextColor(unpack(Theme.MUTED))

    local pitch = content:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    pitch:SetPoint("TOPLEFT", tagline, "BOTTOMLEFT", 0, -16)
    pitch:SetWidth(textWidth)
    pitch:SetJustifyH("LEFT")
    pitch:SetSpacing(4)
    pitch:SetText(table.concat({
        "A clear guide to buying and selling. It keeps a price history for what you "
            .. "carry and tells you, in a sentence, what's worth doing with it.",
        "It watches and advises. It never posts, buys or cancels anything for you.",
        "Type /gw to open it, or left-click the button on your minimap.",
    }, "\n\n"))

    return mount
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
    content:SetSize(PAGE_WIDTH, 1)
    scroll:SetScrollChild(content)

    local masthead = AddMasthead(content)

    local blocks = {}
    for _, section in ipairs(Sections()) do
        AddHeading(content, blocks, section.heading)

        -- Whatever comes first under a heading needs to clear its rule.
        local first = true
        local function Paragraphs(paragraphs)
            for _, paragraph in ipairs(paragraphs or {}) do
                local gap = first and 14 or LINE_GAP + 4
                AddText(content, blocks, "GameFontHighlight", paragraph, 0, gap)
                first = false
            end
        end

        Paragraphs(section.intro)
        for _, item in ipairs(section.list or {}) do
            AddListItem(content, blocks, item, first)
            first = false
        end
        Paragraphs(section.text)
    end

    -- Places every piece under the one before. Done each time the tab is
    -- shown: text measured while its frame is still hidden can come back
    -- the wrong height, and getting it right once it's on screen costs
    -- nothing.
    local function Layout()
        local offset = masthead:GetHeight()
        for _, block in ipairs(blocks) do
            offset = offset + block.gap
            block.region:ClearAllPoints()
            block.region:SetPoint("TOPLEFT", block.x, -offset)
            offset = offset + block.region:GetStringHeight()
        end

        -- The scroll range comes from the child's height, which has to be
        -- set by hand.
        content:SetHeight(offset + 12)
    end

    tab:SetScript("OnShow", Layout)
    Layout()

    return tab
end
