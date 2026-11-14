local _, ns = ...

-- The menu behind a right-click on an item anywhere in Goldwise: its
-- crafting tree, its price history, and a link in chat. Every list that
-- shows items opens this one, so the same click does the same thing
-- wherever it's made. A list can add its own entries above these, as
-- Assets does for keeping an item.

local ItemMenu = {}
ns.ItemMenu = ItemMenu

-- Puts an item's link in chat, opening the chat box first if it's closed.
-- Inserting alone does nothing when there's no chat box open to take it.
local function LinkInChat(itemID, link)
    local _, itemLink = C_Item.GetItemInfo(link or itemID)
    if not itemLink then
        return
    end
    if ChatFrameUtil and ChatFrameUtil.LinkItem then
        ChatFrameUtil.LinkItem(itemID, itemLink)
    elseif ChatEdit_InsertLink then
        ChatEdit_InsertLink(itemLink)
    end
end

--- Opens the menu for an item.
---@param owner table      the frame clicked, which the menu hangs from
---@param itemID number
---@param link string|nil  the item's link, if there's one to hand
---@param extra (fun(root: table))|nil  adds the list's own entries first
---@param onHistory (fun())|false|nil  opens the price history the list's
---        own way, as Assets does, counting every character's bags and
---        banks; the plain history page when nil; false leaves the entry
---        out, for the item's own page
function ItemMenu.Open(owner, itemID, link, extra, onHistory)
    if not itemID then
        return
    end

    MenuUtil.CreateContextMenu(owner, function(_, root)
        root:CreateTitle(ns.ItemName(itemID) or ("Item " .. itemID))
        if extra then
            extra(root)
        end
        root:CreateButton("Crafting tree", function()
            ns.ShowCraftTree(itemID)
        end)
        if onHistory ~= false then
            root:CreateButton("Price history", function()
                if onHistory then
                    onHistory()
                else
                    ns.ShowItemHistory(itemID, link)
                end
            end)
        end
        root:CreateButton("Link in chat", function()
            LinkInChat(itemID, link)
        end)
    end)
end
