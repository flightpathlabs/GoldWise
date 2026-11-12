local _, ns = ...

-- Decides what's worth doing with something the player holds, and says why.
--
-- Nothing in this file talks to the game. It takes numbers in and gives a
-- verdict and a sentence back, which makes the reasoning easy to follow
-- and easy to test.
--
-- The rules lean cautious on purpose. Bad advice costs trust quickly, so
-- when the gain is small or the data is thin, the answer is the safe one.

local Advice = {}
ns.Advice = Advice

Advice.SELL = "sell"
Advice.HOLD = "hold"
Advice.VENDOR = "vendor"
Advice.KEEP = "keep"
Advice.UNKNOWN = "unknown"

-- How far from its usual price something has to be before we remark on it.
local NOTABLE_DIFFERENCE = 0.10

-- Every verdict comes in two voices. The facts are identical; only the
-- delivery changes. The auditor sticks to ordinary accounting words.
--
-- These have to fit on one line of the list, which holds about fifty-five
-- characters, fewer when they're in capitals. The first in-game test
-- clipped several, so check any new one against that.
local PHRASES = {
    noPrice = {
        calm = "No auction price yet. Visit the auction house.",
        auditor = "No price on file. GO TO THE AUCTION HOUSE.",
    },
    underDeposit = {
        calm = "Worth no more than the %s listing deposit. Vendor it.",
        auditor = "Not worth MORE than the %s deposit. Vendor it.",
    },
    underDepositNoVendor = {
        calm = "Worth no more than the %s deposit. Not worth listing.",
        auditor = "Under the %s deposit and no vendor wants it. Clutter.",
    },
    vendorPaysSame = {
        calm = "A vendor pays as much as the auction house would.",
        auditor = "The vendor pays the same. Take the money and move on.",
    },
    thinMargin = {
        calm = "Only %s over vendor price. Not worth the deposit.",
        auditor = "%s over vendor price? You'd risk the deposit for THAT?",
    },
    barelyCoversDeposit = {
        calm = "Would barely cover the listing deposit. Not worth it.",
        auditor = "It barely covers the deposit. That is not a plan.",
    },
    aboveUsual = {
        calm = "Above its usual price. Sell today.",
        auditor = "An ASSET, above its usual price. SELL. TODAY.",
    },
    belowUsual = {
        calm = "Below its usual price. Worth waiting if you can.",
        auditor = "Below its usual price. Do NOT panic-sell. Hold.",
    },
    usual = {
        calm = "Selling at its usual price.",
        auditor = "Priced where it always is. List it and move on.",
    },
    newToUs = {
        calm = "Worth listing. Too little history to judge the timing.",
        auditor = "Worth listing. New file, so no trends yet.",
    },
    keptByChoice = {
        calm = "You're keeping this. Right-click to change your mind.",
        auditor = "A KEEPER, you say. Right-click if you see sense.",
    },
    keptAsTool = {
        calm = "A tool of your trade. Right-click to sell it anyway.",
        auditor = "You NEED this to work. Right-click to argue.",
    },
}

local function Phrase(key, auditor, ...)
    local text = PHRASES[key][auditor and "auditor" or "calm"]
    if select("#", ...) > 0 then
        text = text:format(...)
    end
    return text
end

--- The verdict on something the player isn't selling.
---@param isTool boolean  true if it's kept as a tool of a trade, false if
---        the player chose to keep it
---@param auditor boolean  true for the loud voice
---@return table advice  { verb, reason }, with no proceeds: nothing is for sale
function Advice.ForKept(isTool, auditor)
    return {
        verb = Advice.KEEP,
        reason = Phrase(isTool and "keptAsTool" or "keptByChoice", auditor),
    }
end

--- Works out what to do with a stack of one item.
---@param holding table with:
---   count         how many the player has
---   price         lowest auction price per unit in copper, or nil if unknown
---   vendorPrice   what a vendor pays per unit in copper; nil or 0 if nothing
---   againstUsual  from Stats.AgainstUsual (0.18 is 18% above usual), or nil
---   cut           the auction house's share of a sale, e.g. 0.05
---   auditor       true for the loud voice
---@return table advice  { verb, reason, proceeds, fromVendor }
---        proceeds is what selling the lot at auction should bring in after
---        the cut, and fromVendor what a vendor would pay for it. Both are
---        nil when there's no price to work from.
function Advice.ForHolding(holding)
    local auditor = holding.auditor

    if not holding.price then
        return { verb = Advice.UNKNOWN, reason = Phrase("noPrice", auditor) }
    end

    local gross = holding.price * holding.count
    local proceeds = gross - gross * holding.cut
    local fromVendor = (holding.vendorPrice or 0) * holding.count
    local vendorWantsIt = fromVendor > 0

    local function Verdict(verb, key, ...)
        return {
            verb = verb,
            reason = Phrase(key, auditor, ...),
            proceeds = proceeds,
            fromVendor = fromVendor,
        }
    end

    if gross <= ns.MIN_DEPOSIT then
        local deposit = ns.Money(ns.MIN_DEPOSIT)
        if vendorWantsIt then
            return Verdict(Advice.VENDOR, "underDeposit", deposit)
        end
        return Verdict(Advice.HOLD, "underDepositNoVendor", deposit)
    end

    if vendorWantsIt and proceeds <= fromVendor then
        return Verdict(Advice.VENDOR, "vendorPaysSame")
    end

    -- If it doesn't sell, the deposit is gone. A gain smaller than the
    -- deposit isn't worth that bet.
    local gain = proceeds - fromVendor
    if gain < ns.MIN_DEPOSIT then
        if vendorWantsIt then
            return Verdict(Advice.VENDOR, "thinMargin", ns.Money(gain))
        end
        return Verdict(Advice.HOLD, "barelyCoversDeposit")
    end

    local againstUsual = holding.againstUsual
    if not againstUsual then
        return Verdict(Advice.SELL, "newToUs")
    elseif againstUsual >= NOTABLE_DIFFERENCE then
        return Verdict(Advice.SELL, "aboveUsual")
    elseif againstUsual <= -NOTABLE_DIFFERENCE then
        return Verdict(Advice.HOLD, "belowUsual")
    end
    return Verdict(Advice.SELL, "usual")
end
