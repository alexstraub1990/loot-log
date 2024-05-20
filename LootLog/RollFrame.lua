-- --------------------------------------------------------------------------------
-- Create a frame designed for showing rolls in a scrollable list.
--
-- A list of rolls to show can be set via the <return>::SetItems(items) method,
-- where items is a set of {name, roll, main_roll}, can be cleared by calling
-- <return>::ClearItems(), and their number is returned from GetNumItems().
--
-- The height of the frame is not set directly, but derived from the number of
-- frames and their individual height. The actual size of the frame is constant
-- and can be askes via the <return>::GetFrameSize() method.
--
-- Parameters:
--   name               Global name of the frame
--   parent             Parent frame object for placement within other frames
--   num_item_frames    Number of lines that can be simultaneously shown
--   frame_width        Width of the frame in pixel (minimum: 100)
--   click_callback     Callback function for clicks on items:
--                      <func>(button, name, roll, main roll)
--
-- Returns the created frame that is derived from Frame
-- --------------------------------------------------------------------------------
function CreateRollFrame(name, parent, num_item_frames, frame_width, click_callback)
    local ItemFrame = CreateFrame("Frame", name, parent)

    -- settings for appearance
    ItemFrame.num_item_frames = num_item_frames -- number of frames to show simultaneously
    ItemFrame.frame_width = max(100, frame_width) -- width of the item frame
    ItemFrame.item_height = 20 -- height of a single item line

    -- callback function for clicks
    ItemFrame.click_callback = click_callback -- callback for click events

    -- frames/textures
    ItemFrame.background = {} -- background texture
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
        ItemFrame.background = ItemFrame:CreateTexture()
        ItemFrame.background:SetAllPoints(ItemFrame)
        ItemFrame.background:SetColorTexture(0.2, 0.2, 0.2, 0.5)

        -- create frames for item lines
        for i = 1, ItemFrame.num_item_frames, 1 do
            local item_line = CreateFrame("Frame", name .. "ItemFrame#" .. i, ItemFrame)
            item_line:SetPoint("TOPLEFT", 0, -(i - 1) * ItemFrame.item_height)
            item_line:SetWidth(ItemFrame.frame_width)
            item_line:SetHeight(ItemFrame.item_height)

            item_line.name = item_line:CreateFontString(name .. "ItemName#" .. i, "OVERLAY", "GameFontHighlightExtraSmallLeft")
            item_line.name:SetPoint("LEFT", 5, 0)
            item_line.name:SetWidth(ItemFrame.frame_width - 60)

            item_line.roll = item_line:CreateFontString(name .. "ItemRoll#" .. i, "OVERLAY", "GameFontHighlightExtraSmallLeft")
            item_line.roll:SetPoint("RIGHT", -40, 0)
            item_line.roll:SetWidth(25)

            item_line.main = item_line:CreateFontString(name .. "ItemMain#" .. i, "OVERLAY", "GameFontHighlightExtraSmallLeft")
            item_line.main:SetPoint("RIGHT", -15, 0)
            item_line.main:SetWidth(25)

            table.insert(ItemFrame.item_lines, item_line)
        end

        -- scroll frame
        ItemFrame.ScrollFrame = CreateFrame("ScrollFrame", name .. "ScrollFrame", ItemFrame, "FauxScrollFrameTemplate")
        ItemFrame.ScrollFrame:SetWidth(ItemFrame.frame_width - 22)
        ItemFrame.ScrollFrame:SetHeight(ItemFrame.num_item_frames * ItemFrame.item_height)
        ItemFrame.ScrollFrame:SetPoint("TOPLEFT", 0, 0)
    end

    initialize()

    -- Update visual representation
    local update
    update = function()
        -- adjust scroll position
        local max_scroll_pos = max(1, #ItemFrame.items - ItemFrame.num_item_frames + 1)
        if (ItemFrame.scroll_pos > max_scroll_pos) then ItemFrame.scroll_pos = max_scroll_pos end

        FauxScrollFrame_Update(ItemFrame.ScrollFrame, #ItemFrame.items, ItemFrame.num_item_frames, ItemFrame.item_height)

        -- visually prepare shown item list
        for i = 1, min(#ItemFrame.items, ItemFrame.num_item_frames), 1 do
            local item = ItemFrame.items[ItemFrame.scroll_pos - 1 + i]

            -- set player name, roll, and main roll info
            ItemFrame.item_lines[i].name:SetText(item.name)
            ItemFrame.item_lines[i].roll:SetText(item.roll)
            ItemFrame.item_lines[i].main:SetText(item.main_roll and "100" or "50")

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

    -- add item
    function ItemFrame:AddItem(item)
        table.insert(ItemFrame.items, item)

        update()
    end

    -- get items
    function ItemFrame:GetItems()
        return ItemFrame.items
    end

    -- implement scrolling of the frame
    local function update_scroll()
        FauxScrollFrame_Update(ItemFrame.ScrollFrame, #ItemFrame.items, ItemFrame.num_item_frames, ItemFrame.item_height)
        ItemFrame.scroll_pos = FauxScrollFrame_GetOffset(ItemFrame.ScrollFrame) + 1

        update()
    end

    ItemFrame.ScrollFrame:SetScript("OnVerticalScroll", function(_, offset)
        FauxScrollFrame_OnVerticalScroll(ItemFrame.ScrollFrame, offset, ItemFrame.item_height, update_scroll)
    end)

    -- return created frame
    return ItemFrame
end
