-- user settings
local window_width = 200
local num_items = 15

-- top-level gui frames
local loot_frame = CreateFrame("Frame", "LootLogFrame", UIParent)

local settings_frame = CreateFrame("Frame", "LootLogSettings", UIParent)
local settings_frame_visible = false

-- special frames
local event_load_frame = CreateFrame("Frame")
local event_loot_frame = CreateFrame("Frame")
local scan_frame = CreateFrame("GameTooltip", "LootLogScanTooltip", nil, "GameTooltipTemplate")

-- temporary storage
local item_cache = ItemCache.new()

local loaded_items = 0
local is_loaded = false

-- toggle gui visibility
local toggle_visibility = function()
    if LootLog_frame_visible then
        loot_frame:Hide()
        LootLog_frame_visible = false
    else
        loot_frame:Show()
        LootLog_frame_visible = true
    end
end

-- create timestamp for ordering looted items and filter list
local loot_information = function()
    local index = LootLog_loot_index
    LootLog_loot_index = LootLog_loot_index + 1

    local datetime = C_DateAndTime.GetCurrentCalendarTime()
    datetime.day = datetime.monthDay
    datetime.monthDay = nil
    datetime.weekday = nil

    local zone = GetRealZoneText()

    return { index = index, date = datetime, zone = zone }
end

local item_information_text = function(item_id)
    local item = item_cache:get(item_id)
    local _, link = GetItemInfo(item_id)

    return link
end

local loot_information_text = function(item_id)
    local loot_information = LootLog_looted_items[item_id]

    return item_information_text(item_id) .. ": " .. loot_information.zone .. ", " ..
        loot_information.date.day .. "." .. loot_information.date.month .. "." .. loot_information.date.year .. " " .. 
        loot_information.date.hour .. ":" .. loot_information.date.minute
end

local item_to_chat = function(item_id)
    if ChatFrameEditBox and ChatFrameEditBox:IsVisible() then
        ChatFrameEditBox:Insert(item_cache:get(item_id).link)
    else
        ChatEdit_InsertLink(item_cache:get(item_id).link)
    end
end

-- update shown list
local update_list = function()
    if not is_loaded or LootLog_looted_items == nil then return end

    local sorted_items = {}
    local sorted_keys = {}

    for item_id, info in pairs(LootLog_looted_items) do
        sorted_items[info.index] = item_id
        table.insert(sorted_keys, info.index)
    end

    table.sort(sorted_keys)

    local shown_items = {}

    for _, key in ipairs(sorted_keys) do
        local item = item_cache:get(sorted_items[key])

        local discard = false
        local keep = true

        -- filter by item quality
        if item.quality < LootLog_min_quality then discard = true end

        -- filter by equippability (hack! scan tooltip for red text color; might break if other addons modify the tooltip)
        scan_frame:ClearLines()
        scan_frame:SetItemByID(item.id)

        local function scan_tooltip(...)
            for i = 1, select("#", ...) do
                local region = select(i, ...)

                if region and region:GetObjectType() == "FontString" then
                    local text = region:GetText()
                    local r, g, b = region:GetTextColor()

                    if (text and r > 0.9 and g < 0.2 and b < 0.2) then
                        return false
                    end
                end
            end

            return true
        end

        discard = discard or (LootLog_equippable and not (IsEquippableItem(item.id) and scan_tooltip(scan_frame:GetRegions())))

        -- filter by filter list
        if LootLog_use_filter_list then
            keep = false

            for filter_info, _ in pairs(LootLog_filter_list) do
                local filter_id = type(filter_info) == "table" and filter_info[1] or filter_info

                if item.id == filter_id then keep = true end
            end
        end

        if keep and not discard then
            table.insert(shown_items, item)
        end
    end

    if (LootLog_open_on_loot and not LootLog_frame_visible and #shown_items ~= loot_frame.field:GetNumItems()) then
        toggle_visibility()
    end

    loot_frame.field:SetItems(shown_items)
end

-- update filter list
local update_filter = function()
    if not is_loaded or LootLog_filter_list == nil then return end

    local sorted_items = {}
    local sorted_keys = {}

    for item_id, index in pairs(LootLog_filter_list) do
        sorted_items[index] = item_id
        table.insert(sorted_keys, index)
    end

    table.sort(sorted_keys)

    local shown_items = {}

    for _, key in ipairs(sorted_keys) do
        local item = item_cache:get(sorted_items[key])

        table.insert(shown_items, item)
    end

    settings_frame.filter:SetItems(shown_items)
end

-- handle click on an item
local event_click_item = function(mouse_key, item_id)
    local handler = {
        ["RightButton"] = function(item_id) LootLog_looted_items[item_id] = nil; update_list() end,
        ["LeftButton"] = function(item_id) if IsShiftKeyDown() then item_to_chat(item_id) else print(loot_information_text(item_id)) end end
    }

    for item_info, _ in pairs(LootLog_looted_items) do
        if item_info == item_id then
            handler[mouse_key](item_id)
        end
    end
end

-- handle click on an item in the filter list
local event_click_filter = function(mouse_key, item_id)
    local handler = {
        ["RightButton"] = function(item_id) LootLog_filter_list[item_id] = nil; update_filter(); update_list() end,
        ["LeftButton"] = function(item_id) if IsShiftKeyDown() then item_to_chat(item_id) else print(item_information_text(item_id)) end end
    }

    for item_info, _ in pairs(LootLog_filter_list) do
        if item_info == item_id then
            handler[mouse_key](item_id)
        end
    end
end

local event_addon_loaded = function(_, _, addon)
    if addon == "LootLog" then
        -- options
        if LootLog_frame_visible == nil then
            LootLog_frame_visible = false
        end
        if (LootLog_frame_visible) then
            loot_frame:Show()
        else
            loot_frame:Hide()
        end

        if LootLog_min_quality == nil then
            LootLog_min_quality = 4
        end

        if LootLog_equippable == nil then
            LootLog_equippable = false
        end

        if LootLog_open_on_loot == nil then
            LootLog_open_on_loot = false
        end

        if LootLog_use_filter_list == nil then
            LootLog_use_filter_list = false
        end

        -- stored loot and filter
        if LootLog_loot_index == nil then
            LootLog_loot_index = 0
        end
        if LootLog_filter_index == nil then
            LootLog_filter_index = 0
        end

        if not LootLog_looted_items or next(LootLog_looted_items) == nil then
            LootLog_looted_items = {}
        else
            for item_id, item_info in pairs(LootLog_looted_items) do
                if not item_info or type(item_info) ~= "table" or not item_info.index then
                    LootLog_looted_items = {}
                end
            end
        end
        if not LootLog_filter_list or next(LootLog_filter_list) == nil then
            LootLog_filter_list = {}
        else
            for item_id, item_info in pairs(LootLog_filter_list) do
                if not item_info or type(item_info) ~= "number" then
                    LootLog_filter_list = {}
                end
            end
        end

        local needed_items = 0
        for _, _ in pairs(LootLog_looted_items) do
            needed_items = needed_items + 1
        end
        for _, _ in pairs(LootLog_filter_list) do
            needed_items = needed_items + 1
        end

        for item_id, _ in pairs(LootLog_looted_items) do
            item_cache:getAsync(item_id,
                function() loaded_items = loaded_items + 1; if loaded_items == needed_items then is_loaded = true; update_filter(); update_list() end end)
        end
        for item_id, _ in pairs(LootLog_filter_list) do
            item_cache:getAsync(item_id,
                function() loaded_items = loaded_items + 1; if loaded_items == needed_items then is_loaded = true; update_filter(); update_list() end end)
        end

        -- minimap button
        if LootLog_minimap == nil then
            LootLog_minimap = {
                ["minimapPos"] = 200.0,
                ["hide"] = false,
            }
        end

        local miniButton = LibStub("LibDataBroker-1.1"):NewDataObject("LootLog", {
            type = "data source",
            text = "Loot Log",
            icon = "Interface\\HELPFRAME\\HelpIcon-KnowledgeBase",
            OnClick = function() toggle_visibility() end,
            OnTooltipShow = function(tooltip) if not tooltip or not tooltip.AddLine then return end; tooltip:AddLine("Loot Log") end,
        })

        local icon = LibStub("LibDBIcon-1.0", true)
        icon:Register("LootLog", miniButton, LootLog_minimap)

        -- initialize settings
        UIDropDownMenu_SetText(settings_frame.quality_options, LootLog_Locale.qualities[LootLog_min_quality + 1])

        settings_frame.equippable:SetChecked(LootLog_equippable)
        settings_frame.auto_open:SetChecked(LootLog_open_on_loot)
        settings_frame.use_filter:SetChecked(LootLog_use_filter_list)

        -- initialize lists if possible
        if item_cache:loaded() then
            is_loaded = true
    
            update_filter()
            update_list()
        end
    end
end

-- main function for parsing loot messages
local event_looted = function(_, _, text)
    -- parse item information
    local _, item_id_start = string.find(text, "|Hitem:")
    local text = string.sub(text, item_id_start + 1, -1)

    local item_id_end, _ = string.find(text, ":")
    text = string.sub(text, 1, item_id_end - 1)

    local item_id = tonumber(text)

    -- show and fill frame
    local found = false

    for item_info, _ in pairs(LootLog_looted_items) do
        if item_info == item_id then found = true end
    end

    if not found then
        item_cache:getAsync(item_id, function(item) LootLog_looted_items[item.id] = loot_information(); update_list() end)
    end
end

-- handle adding and item to the filter list
local event_add_item = function(item_id)
    if not C_Item.DoesItemExistByID(item_id) then
        return
    end

    -- show and fill frame
    local found = false

    for item_info, _ in pairs(LootLog_filter_list) do
        if item_info == item_id then found = true end
    end

    if not found then
        local index = LootLog_filter_index
        LootLog_filter_index = LootLog_filter_index + 1

        item_cache:getAsync(item_id, function(item) LootLog_filter_list[item.id] = index; update_filter(); update_list() end)
    end
end

-- initialize frame
do
    -- create item frame
    local item_frame = CreateItemFrame("LootLogLog", loot_frame, num_items, window_width - 10, event_click_item)

    -- create main frame
    loot_frame:SetFrameStrata("MEDIUM")
    loot_frame:SetWidth(window_width)
    loot_frame:SetHeight(80 + select(2, item_frame:GetFrameSize()))
    loot_frame:SetPoint("CENTER", 0, 0)
    loot_frame:SetMovable(true)
    loot_frame:EnableMouse(true)
    loot_frame:RegisterForDrag("LeftButton")
    loot_frame:SetScript("OnDragStart", function(self) self:StartMoving() end)
    loot_frame:SetScript("OnDragStart", function(self) self:StartMoving() end)
    loot_frame:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)

    loot_frame.background = loot_frame:CreateTexture()
    loot_frame.background:SetAllPoints(loot_frame)
    loot_frame.background:SetColorTexture(0.1, 0.1, 0.1, 0.5)

    loot_frame.title = loot_frame:CreateFontString("LootLogTitle", "OVERLAY", "GameFontNormal")
    loot_frame.title:SetPoint("TOPLEFT", 5, -5)
    loot_frame.title:SetText(LootLog_Locale.title)

    loot_frame.close = CreateFrame("Button", "LootLogSettingsClose", loot_frame, "UIPanelCloseButton")
    loot_frame.close:SetPoint("TOPRIGHT", 0, 2)
    loot_frame.close:SetScript("OnClick", function(_, button) if (button == "LeftButton") then LootLog_frame_visible = false; loot_frame:Hide() end end)

    loot_frame.field = item_frame
    loot_frame.field:SetPoint("TOPLEFT", 5, -25)

    -- roll 100 button
    loot_frame.roll_main = CreateButton("LootLogRoll100", loot_frame, LootLog_Locale.roll_main, 100, 25, function(self, ...) RandomRoll(1, 100) end)
    loot_frame.roll_main:SetPoint("BOTTOMLEFT", 2, 27)

    -- roll 50 button
    loot_frame.roll_off = CreateButton("LootLogRoll50", loot_frame, LootLog_Locale.roll_off, 100, 25, function(self, ...) RandomRoll(1, 50) end)
    loot_frame.roll_off:SetPoint("BOTTOMRIGHT", -2, 27)

    -- clear button
    loot_frame.clear = CreateButton("LootLogClear", loot_frame, LootLog_Locale.clear, 100, 25, function(self, ...)
        for item_id, _ in pairs(LootLog_looted_items) do LootLog_looted_items[item_id] = nil end; LootLog_loot_index = 0; update_list() end)
    loot_frame.clear:SetPoint("BOTTOMRIGHT", -2, 2)

    -- settings button
    loot_frame.settings = CreateButton("LootLogSettings", loot_frame, LootLog_Locale.settings, 100, 25)
    loot_frame.settings:SetPoint("BOTTOMLEFT", 2, 2)

    -- initially hide frame
    loot_frame:Hide()



    -- create item frame for the settings
    local filter_frame = CreateItemFrame("LootLogFilter", settings_frame, 10, 240, event_click_filter)

    -- initialize settings window
    settings_frame:SetFrameStrata("HIGH")
    settings_frame:SetWidth(250)
    settings_frame:SetHeight(170 + select(2, filter_frame:GetFrameSize()))
    settings_frame:SetPoint("CENTER", 150, 0)
    settings_frame:SetMovable(true)
    settings_frame:EnableMouse(true)
    settings_frame:RegisterForDrag("LeftButton")
    settings_frame:SetScript("OnDragStart", function(self) self:StartMoving() end)
    settings_frame:SetScript("OnDragStart", function(self) self:StartMoving() end)
    settings_frame:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)

    settings_frame.background = settings_frame:CreateTexture()
    settings_frame.background:SetAllPoints(settings_frame)
    settings_frame.background:SetColorTexture(0.1, 0.1, 0.1, 0.5)

    settings_frame.title = settings_frame:CreateFontString("LootLogSettingsTitle", "OVERLAY", "GameFontNormal")
    settings_frame.title:SetPoint("TOPLEFT", 5, -5)
    settings_frame.title:SetText(LootLog_Locale.title .. " — " .. LootLog_Locale.settings)

    settings_frame.close = CreateFrame("Button", "LootLogSettingsClose", settings_frame, "UIPanelCloseButton")
    settings_frame.close:SetPoint("TOPRIGHT", 0, 2)
    settings_frame.close:SetScript("OnClick", function(_, button) if (button == "LeftButton") then settings_frame_visible = false; settings_frame:Hide() end end)

    _G["LootLogSettings"] = settings_frame
    tinsert(UISpecialFrames, "LootLogSettings")

    settings_frame:SetScript("OnHide", function() settings_frame_visible = false end)

    -- filter by quality
    local quality_y = -30

    settings_frame.quality_label = settings_frame:CreateFontString("LootLogQualityLabel", "OVERLAY", "GameFontHighlight")
    settings_frame.quality_label:SetPoint("TOPLEFT", 10, quality_y - 7)
    settings_frame.quality_label:SetText(LootLog_Locale.min_quality)

    settings_frame.quality_options = CreateFrame("Frame", "LootLogQualityLabel", settings_frame, "UIDropDownMenuTemplate")
    settings_frame.quality_options:SetPoint("TOPRIGHT", 10, -30)

    UIDropDownMenu_SetWidth(settings_frame.quality_options, 100)
    UIDropDownMenu_Initialize(settings_frame.quality_options,
        function(self, _, _)
            local info = UIDropDownMenu_CreateInfo()
            info.func = function(self, arg1, _, _) UIDropDownMenu_SetText(settings_frame.quality_options, LootLog_Locale.qualities[arg1 + 1]); LootLog_min_quality = arg1; update_list() end

            info.text, info.arg1, info.checked = LootLog_Locale.qualities[1], 0, LootLog_min_quality == 0
            UIDropDownMenu_AddButton(info)

            info.text, info.arg1, info.checked = LootLog_Locale.qualities[2], 1, LootLog_min_quality == 1
            UIDropDownMenu_AddButton(info)

            info.text, info.arg1, info.checked = LootLog_Locale.qualities[3], 2, LootLog_min_quality == 2
            UIDropDownMenu_AddButton(info)

            info.text, info.arg1, info.checked = LootLog_Locale.qualities[4], 3, LootLog_min_quality == 3
            UIDropDownMenu_AddButton(info)

            info.text, info.arg1, info.checked = LootLog_Locale.qualities[5], 4, LootLog_min_quality == 4
            UIDropDownMenu_AddButton(info)

            info.text, info.arg1, info.checked = LootLog_Locale.qualities[6], 5, LootLog_min_quality == 5
            UIDropDownMenu_AddButton(info)
        end)

    -- option to show only equippable loot
    local equippable_y = -60

    settings_frame.equippable_label = settings_frame:CreateFontString("LootLogEquippableLabel", "OVERLAY", "GameFontHighlight")
    settings_frame.equippable_label:SetPoint("TOPLEFT", 10, equippable_y - 6)
    settings_frame.equippable_label:SetText(LootLog_Locale.equippable)

    settings_frame.equippable = CreateFrame("CheckButton", "LootLogEquippableCheckbox", settings_frame, "UICheckButtonTemplate")
    settings_frame.equippable:SetSize(25, 25)
    settings_frame.equippable:SetPoint("TOPRIGHT", -8, equippable_y)
    settings_frame.equippable:HookScript("OnClick", function(self, button, ...) LootLog_equippable = settings_frame.equippable:GetChecked(); update_list() end)

    -- option to open frame automatically on new loot
    local auto_open_y = -83

    settings_frame.auto_open_label = settings_frame:CreateFontString("LootLogAutoOpenLabel", "OVERLAY", "GameFontHighlight")
    settings_frame.auto_open_label:SetPoint("TOPLEFT", 10, auto_open_y - 6)
    settings_frame.auto_open_label:SetText(LootLog_Locale.auto_open)

    settings_frame.auto_open = CreateFrame("CheckButton", "LootLogAutoOpenCheckbox", settings_frame, "UICheckButtonTemplate")
    settings_frame.auto_open:SetSize(25, 25)
    settings_frame.auto_open:SetPoint("TOPRIGHT", -8, auto_open_y)
    settings_frame.auto_open:HookScript("OnClick", function(self, button, ...) LootLog_open_on_loot = settings_frame.auto_open:GetChecked() end)

    -- option to add only items to the loot list that are in the following priority list
    local filter_y = -106

    settings_frame.use_filter_label = settings_frame:CreateFontString("LootLogFilterLabel", "OVERLAY", "GameFontHighlight")
    settings_frame.use_filter_label:SetPoint("TOPLEFT", 10, filter_y - 6)
    settings_frame.use_filter_label:SetText(LootLog_Locale.filter)

    settings_frame.use_filter = CreateFrame("CheckButton", "LootLogFilterCheckbox", settings_frame, "UICheckButtonTemplate")
    settings_frame.use_filter:SetSize(25, 25)
    settings_frame.use_filter:SetPoint("TOPRIGHT", -8, filter_y)
    settings_frame.use_filter:HookScript("OnClick", function(self, button, ...) LootLog_use_filter_list = settings_frame.use_filter:GetChecked(); update_list() end)

    settings_frame.filter = filter_frame
    settings_frame.filter:SetPoint("TOPLEFT", 5, filter_y - 32)

    settings_frame.item_id = CreateFrame("EditBox", "LootLogFilterItem", settings_frame)
    settings_frame.item_id:SetSize(80, 22)
    settings_frame.item_id:SetPoint("BOTTOMLEFT", 5, 5)
    settings_frame.item_id:SetFontObject(ChatFontNormal)
    settings_frame.item_id:SetAutoFocus(false)
    settings_frame.item_id:SetNumeric(true)
    settings_frame.item_id:SetScript("OnEnterPressed", function(self, ...)
        event_add_item(settings_frame.item_id:GetText()); settings_frame.item_id:ClearFocus(); settings_frame.item_id:SetText("") end)
    settings_frame.item_id:SetScript("OnEscapePressed", function(self, ...)
        settings_frame.item_id:ClearFocus(); settings_frame.item_id:SetText("") end)

    settings_frame.item_id.background = settings_frame.item_id:CreateTexture()
    settings_frame.item_id.background:SetAllPoints(settings_frame.item_id)
    settings_frame.item_id.background:SetColorTexture(0.5, 0.5, 0.5, 0.5)

    settings_frame.item_add = CreateButton("LootLogFilterAdd", settings_frame, LootLog_Locale.add_item, 100, 25, function(self, ...)
        event_add_item(settings_frame.item_id:GetText()); settings_frame.item_id:SetText("") end)
    settings_frame.item_add:SetPoint("BOTTOMRIGHT", -55, 3)

    settings_frame.clear_filter = CreateButton("LootLogFilterClear", settings_frame, LootLog_Locale.clear, 50, 25, function(self, ...)
        for item_id, _ in pairs(LootLog_filter_list) do LootLog_filter_list[item_id] = nil end; LootLog_filter_index = 0; update_filter(); update_list() end)
    settings_frame.clear_filter:SetPoint("BOTTOMRIGHT", -2, 3)

    -- initially hide settings frame
    settings_frame:Hide()



    -- scripts
    loot_frame.settings:SetScript("OnClick", function(self, ...) if (settings_frame_visible) then settings_frame_visible = false; settings_frame:Hide()
        else settings_frame_visible = true; settings_frame:Show() end; UIDropDownMenu_SetText(settings_frame.quality_options, LootLog_Locale.qualities[LootLog_min_quality + 1]) end)

    scan_frame:SetOwner(WorldFrame, "ANCHOR_NONE")
    scan_frame:AddFontStrings(
        scan_frame:CreateFontString("$parentTextLeft1", nil, "GameTooltipText"),
        scan_frame:CreateFontString("$parentTextRight1", nil, "GameTooltipText"));
        
    event_load_frame:RegisterEvent("ADDON_LOADED")
    event_load_frame:SetScript("OnEvent", event_addon_loaded)

    event_loot_frame:RegisterEvent("CHAT_MSG_LOOT")
    event_loot_frame:SetScript("OnEvent", event_looted)
end

-- slash commands
SLASH_LOOTLOG1 = "/ll"
SLASH_LOOTLOG2 = "/lootlog"

SlashCmdList["LOOTLOG"] = toggle_visibility
