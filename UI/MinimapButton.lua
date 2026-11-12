local _, ns = ...

-- The button on the edge of the minimap. Left-click opens the window,
-- right-click opens the options, and it can be dragged around the rim.
--
-- This is hand-built rather than using the usual button library, to keep
-- Goldwise free of dependencies. It follows the same conventions, though:
-- the same art and size as every other minimap button, and a name that
-- button-tidying addons recognise and will gather up.

local Theme = ns.Theme

-- How far outside the minimap's edge the button's centre sits.
local EDGE_OFFSET = 5

local button

-- Puts the button on the minimap's rim at the saved angle.
local function Place()
    local angle = math.rad(ns.settings.minimapAngle)
    local x, y = math.cos(angle), math.sin(angle)
    local halfWidth = Minimap:GetWidth() / 2 + EDGE_OFFSET
    local halfHeight = Minimap:GetHeight() / 2 + EDGE_OFFSET

    -- Minimap addons that reshape the map announce the shape through this
    -- function. On a square map the button follows the edges and corners
    -- instead of cutting across them on a circle.
    local shape = GetMinimapShape and GetMinimapShape() or "ROUND"
    if shape == "ROUND" then
        x, y = x * halfWidth, y * halfHeight
    else
        local reach = math.sqrt(2)
        x = math.max(-halfWidth, math.min(x * halfWidth * reach, halfWidth))
        y = math.max(-halfHeight, math.min(y * halfHeight * reach, halfHeight))
    end

    button:ClearAllPoints()
    button:SetPoint("CENTER", Minimap, "CENTER", x, y)
end

-- While dragging: point the button at wherever the cursor is, measured as
-- an angle from the minimap's centre.
local function FollowCursor()
    local centerX, centerY = Minimap:GetCenter()
    local cursorX, cursorY = GetCursorPosition()
    local scale = Minimap:GetEffectiveScale()

    ns.settings.minimapAngle =
        math.deg(math.atan2(cursorY / scale - centerY, cursorX / scale - centerX))
    Place()
end

local function ShowTooltip(self)
    GameTooltip:SetOwner(self, "ANCHOR_LEFT")
    GameTooltip:AddLine("Goldwise", unpack(Theme.COIN))
    GameTooltip:AddLine("Left-click to open.", 1, 1, 1)
    GameTooltip:AddLine("Right-click for options.", 1, 1, 1)
    GameTooltip:AddLine("Drag to move.", unpack(Theme.MUTED))
    GameTooltip:Show()
end

local function Create()
    -- The name matters: addons that collect minimap buttons look for
    -- "MinimapButton" in it.
    local frame = CreateFrame("Button", "GoldwiseMinimapButton", Minimap)
    frame:SetSize(31, 31)
    frame:SetFrameStrata("MEDIUM")
    frame:SetFrameLevel(8)
    frame:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")

    -- The standard look: a dark disc, the icon, and the gold ring on top.
    -- The sizes are the ones other addons' buttons use on this client, so
    -- ours lines up with its neighbours.
    local background = frame:CreateTexture(nil, "BACKGROUND")
    background:SetSize(24, 24)
    background:SetPoint("CENTER")
    background:SetTexture("Interface\\Minimap\\UI-Minimap-Background")

    local icon = frame:CreateTexture(nil, "ARTWORK")
    icon:SetSize(18, 18)
    icon:SetPoint("CENTER")
    icon:SetTexture(Theme.ICON)

    -- The icon is square and the ring is round, so trim its corners.
    local mask = frame:CreateMaskTexture()
    mask:SetAllPoints(icon)
    mask:SetTexture(
        "Interface\\CharacterFrame\\TempPortraitAlphaMask",
        "CLAMPTOBLACKADDITIVE",
        "CLAMPTOBLACKADDITIVE"
    )
    icon:AddMaskTexture(mask)

    local ring = frame:CreateTexture(nil, "OVERLAY")
    ring:SetSize(50, 50)
    ring:SetPoint("TOPLEFT")
    ring:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")

    frame:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    frame:SetScript("OnClick", function(_, mouseButton)
        if mouseButton == "RightButton" then
            ns.OpenOptions()
        else
            ns.ToggleWindow()
        end
    end)

    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", function(self)
        GameTooltip:Hide()
        self:SetScript("OnUpdate", FollowCursor)
    end)
    frame:SetScript("OnDragStop", function(self)
        self:SetScript("OnUpdate", nil)
    end)

    frame:SetScript("OnEnter", ShowTooltip)
    frame:SetScript("OnLeave", GameTooltip_Hide)

    -- A soft ring of light for when there's something worth doing. It
    -- lives on a child frame because that's what the fade is applied to.
    local glow = CreateFrame("Frame", nil, frame)
    glow:SetSize(38, 38)
    glow:SetPoint("CENTER")
    glow:Hide()

    local light = glow:CreateTexture(nil, "OVERLAY")
    light:SetAllPoints()
    light:SetBlendMode("ADD")
    light:SetTexture("Interface\\TutorialFrame\\minimap-glow")

    local pulse = glow:CreateAnimationGroup()
    pulse:SetLooping("BOUNCE")
    local fade = pulse:CreateAnimation("Alpha")
    fade:SetFromAlpha(0.7)
    fade:SetToAlpha(0.1)
    fade:SetDuration(1.2)

    frame.Glow = glow
    frame.Pulse = pulse

    return frame
end

-- Whether the button should currently be pulsing. Remembered here so it
-- survives the button being created, hidden or shown later.
local wantsAttention = false

local function UpdateAttention()
    if not button then
        return
    end

    -- The glow is set outright rather than only when the pulse is running:
    -- hiding the button can stop the animation behind our back, and the
    -- glow mustn't be left lit when that happens.
    button.Glow:SetShown(wantsAttention)
    if not wantsAttention then
        button.Pulse:Stop()
    elseif not button.Pulse:IsPlaying() then
        button.Pulse:Play()
    end
end

--- Starts or stops the button's pulse.
---@param attention boolean  true when there's something worth the player's time
function ns.SetButtonAttention(attention)
    wantsAttention = attention and true or false
    UpdateAttention()
end

-- Shows or hides the button to match the player's setting.
local function Update()
    if ns.settings.minimapButton then
        button = button or Create()
        Place()
        button:Show()
        UpdateAttention()
    elseif button then
        button:Hide()
    end
end

ns.OnEvent("PLAYER_LOGIN", Update)
ns.Subscribe("SETTINGS_CHANGED", Update)
