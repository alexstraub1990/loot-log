-- --------------------------------------------------------------------------------
-- Create a frame designed for showing items in a scrollable list.
--
-- A list of items to show can be set via the <return>::SetItems(items) method,
-- where items is a set of {id, name, quality}, can be cleared by calling
-- <return>::ClearItems(), and their number is returned from GetNumItems().
--
-- The height of the frame is not set directly, but derived from the number of
-- frames and their individual height. The actual size of the frame is constant
-- and can be askes via the <return>::GetFrameSize() method.
--
-- Parameters:
--   name               Global name of the frame
--   parent             Parent frame object for placement within other frames
--   num_item_frames    Number of items that can be simultaneously shown
--   frame_width        Width of the frame in pixel (minimum: 100)
--   click_callback     Callback function for clicks on items: <func>(button, item)
--
-- Returns the created frame that is derived from Frame
-- --------------------------------------------------------------------------------
function CreateItemFrame(name, parent, num_item_frames, frame_width, click_callback)
    local ItemFrame = CreateFrame("Frame", name, parent)

    -- settings for appearance
    ItemFrame.num_item_frames = num_item_frames -- number of frames to show simultaneously
    ItemFrame.frame_width = max(100, frame_width) -- width of the item frame
    ItemFrame.item_height = 20 -- height of a single item line

    -- callback function for clicks
    ItemFrame.click_callback = click_callback -- callback for click events

    -- frames/textures
    ItemFrame.background = {} -- background texture
    ItemFrame.up = {} -- button for scrolling up
    ItemFrame.down = {} -- button for scrolling down
    ItemFrame.item_lines = {} -- individual frames for items

    -- stored values
    ItemFrame.items = {} -- list of items to show
    ItemFrame.scroll_pos = 1 -- scrolling position within the list

    -- initialize item frame
    local function initialize()
        -- set frame size
        ItemFrame:SetWidth(ItemFrame.frame_width)
        ItemFrame:SetHeight(ItemFrame.num_item_frames * ItemFrame.item_height)

        -- set background texture
        ItemFrame.background  = ItemFrame:CreateTexture()
        ItemFrame.background:SetAllPoints(ItemFrame)
        ItemFrame.background:SetColorTexture(0.2, 0.2, 0.2, 0.5)

        -- create button for scrolling up
        ItemFrame.up = CreateFrame("Button", name .. "Up", ItemFrame, "UIPanelScrollUpButtonTemplate")
        ItemFrame.up:SetPoint("TOPRIGHT", 0, 0)

        -- create button for scrolling down
        ItemFrame.down = CreateFrame("Button", name .. "Down", ItemFrame, "UIPanelScrollDownButtonTemplate")
        ItemFrame.down:SetPoint("BOTTOMRIGHT", 0, 0)

        -- create frames for item lines
        for i = 1, ItemFrame.num_item_frames, 1 do
            local item_line = CreateFrame("Frame", name .. "ItemFrame#" .. i, ItemFrame)
            item_line:SetPoint("TOPLEFT", 0, -(i - 1) * ItemFrame.item_height)
            item_line:SetWidth(ItemFrame.frame_width)
            item_line:SetHeight(ItemFrame.item_height)

            item_line.icon = item_line:CreateTexture(name .. "ItemIcon#" .. i, "BACKGROUND")
            item_line.icon:SetPoint("TOPLEFT", 0, 0)
            item_line.icon:SetWidth(ItemFrame.item_height)
            item_line.icon:SetHeight(ItemFrame.item_height)

            item_line.icon_btn = CreateFrame("Button", name .. "ItemIconBtn#" .. i, item_line)
            item_line.icon_btn:SetPoint("TOPLEFT", 0, 0)
            item_line.icon_btn:SetWidth(ItemFrame.frame_width - 20)
            item_line.icon_btn:SetHeight(ItemFrame.item_height)

            item_line.name = item_line:CreateFontString(name .. "ItemName#" .. i, "OVERLAY", "GameFontHighlightExtraSmallLeft")
            item_line.name:SetPoint("LEFT", ItemFrame.item_height + 5, 0)
            item_line.name:SetWidth(ItemFrame.frame_width - ItemFrame.item_height - 5 - 20)

            table.insert(ItemFrame.item_lines, item_line)
        end
    end

    initialize()

    -- implement scrolling of the frame triggered by the up- and down-buttons
    local function scroll(direction)
        ItemFrame.scroll_pos = ItemFrame.scroll_pos + direction

        if (ItemFrame.scroll_pos < 1) then
            ItemFrame.scroll_pos = 1
        end
    end

    -- Update visual representation
    local update
    update = function()
        -- adjust scroll position
        local max_scroll_pos = max(1, #ItemFrame.items - ItemFrame.num_item_frames + 1)
        if (ItemFrame.scroll_pos > max_scroll_pos) then ItemFrame.scroll_pos = max_scroll_pos end

        -- visually prepare shown item list
        for i = 1, min(#ItemFrame.items, ItemFrame.num_item_frames), 1 do
            local item = ItemFrame.items[ItemFrame.scroll_pos - 1 + i]

            local item_color = {GetItemQualityColor(item.quality)}

            -- set icon texture
            ItemFrame.item_lines[i].icon:SetTexture(GetItemIcon(item.id))

            -- create tool tip and make icon and text clickable
            ItemFrame.item_lines[i].icon_btn:SetAttribute("type", "item");
            ItemFrame.item_lines[i].icon_btn:SetAttribute("item", item.id);
            ItemFrame.item_lines[i].icon_btn:SetScript("OnEnter", function(self) GameTooltip:SetOwner(self, "ANCHOR_CURSOR"); GameTooltip:ClearLines(); GameTooltip:SetItemByID(self:GetAttribute("item")); GameTooltip:Show() end)
            ItemFrame.item_lines[i].icon_btn:SetScript("OnLeave", function(self) GameTooltip:Hide() end)
            ItemFrame.item_lines[i].icon_btn:SetScript("OnMouseUp", function(self, button, ...) click_callback(button, self:GetAttribute("item")); update() end)

            ItemFrame.item_lines[i].name:SetTextColor(item_color[1], item_color[2], item_color[3])
            ItemFrame.item_lines[i].name:SetText(item.name)

            ItemFrame.item_lines[i]:Show()
        end

        -- hide unused items
        for i = #ItemFrame.items + 1, ItemFrame.num_item_frames, 1 do
            ItemFrame.item_lines[i]:Hide()
        end
    end

    -- calculate frame size and return it -> {width, height}
    function ItemFrame:GetFrameSize()
        return ItemFrame.frame_width, ItemFrame.num_item_frames * ItemFrame.item_height
    end

    -- number of items currently in the list
    function ItemFrame:GetNumItems()
        return #ItemFrame.items
    end

    -- clear all items
    function ItemFrame:ClearItems()
        for i = #ItemFrame.items, 1, -1 do table.remove(ItemFrame.items, i) end

        update()
    end

    -- set items
    function ItemFrame:SetItems(items)
        ItemFrame.items = items

        update()
    end

    -- set scripts
    ItemFrame.up:SetScript("OnClick", function(self, ...) scroll(-1); update() end)
    ItemFrame.down:SetScript("OnClick", function(self, ...) scroll(1); update() end)

    -- return created frame
    return ItemFrame
end
