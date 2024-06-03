-- user settings
local window_width = 200
local num_items = 15

-- top-level gui frames
local loot_frame = CreateFrame("Frame", "LootLogFrame", UIParent)
local settings_frame = CreateFrame("Frame", "LootLogSettings", UIParent)
local info_frame = CreateFrame("Frame", "LootLogInfo", UIParent)
local roll_frame = CreateFrame("Frame", "LootLogRoll", UIParent)

-- special frames
local event_load_frame = CreateFrame("Frame")
local event_loot_frame = CreateFrame("Frame")
local event_gargul_frame = CreateFrame("Frame")
local event_roll_frame = CreateFrame("Frame")
local scan_frame = CreateFrame("GameTooltip", "LootLogScanTooltip", nil, "GameTooltipTemplate")

-- temporary storage
local item_cache = ItemCache.new()

local roll_item = nil
local roll_started = false
local roll_end_time = 0

local loaded_items = 0
local is_loaded = false

-- toggle gui visibility
local toggle_visibility = function()
    if loot_frame:IsVisible() then
        loot_frame:Hide()
        LootLog_frame_visible = false
    else
        loot_frame:Show()
        LootLog_frame_visible = true
    end
end

-- create timestamp for ordering looted items and filter list
local loot_information = function(source, amount)
    local index = LootLog_loot_index
    LootLog_loot_index = LootLog_loot_index + 1

    local datetime = C_DateAndTime.GetCurrentCalendarTime()
    datetime.day = datetime.monthDay
    datetime.monthDay = nil
    datetime.weekday = nil

    local zone = GetRealZoneText()

    return { index = index, date = datetime, zone = zone, source = source, amount = amount }
end

local item_information_text = function(item_id)
    local item = item_cache:get(item_id)
    local _, link = GetItemInfo(item_id)

    return link
end

local loot_information_text = function(item_id)
    local loot_information = LootLog_looted_items[item_id]

    local function pad(value, num)
        return string.rep("0", num - string.len(value)) .. value
    end

    return item_information_text(item_id) .. ": " .. loot_information.zone .. ", " ..
        pad(loot_information.date.day, 2) .. "." .. pad(loot_information.date.month, 2) .. "." .. loot_information.date.year .. " " ..
        pad(loot_information.date.hour, 2) .. ":" .. pad(loot_information.date.minute, 2) ..
        (loot_information["amount"] and " (" .. LootLog_Locale.dropped_before .. loot_information.amount .. LootLog_Locale.dropped_after .. "; " .. LootLog_Locale.source .. ": " .. loot_information.source .. ")" or "")
end

local item_to_chat = function(item_id)
    if ChatFrameEditBox and ChatFrameEditBox:IsVisible() then
        ChatFrameEditBox:Insert(item_cache:get(item_id).link)
    else
        ChatEdit_InsertLink(item_cache:get(item_id).link)
    end
end

local announce = function(message)
    if IsInRaid() then
        SendChatMessage(message, "RAID_WARNING")
    elseif IsInGroup() then
        SendChatMessage(message, "PARTY")
    else
        print("Not in a group: (" .. message .. ")")
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

    local sort_function = LootLog_invertsorting and function(a, b) return a > b end or function(a, b) return a < b end
    table.sort(sorted_keys, sort_function)

    local shown_items = {}

    for _, key in ipairs(sorted_keys) do
        local item = item_cache:get(sorted_items[key])

        local discard = false
        local keep = true

        -- filter by item quality
        if item.quality < LootLog_min_quality then discard = true end

        -- filter by source
        if LootLog_source and LootLog_source ~= 0 then
            if LootLog_looted_items[sorted_items[key]].source == "loot" and LootLog_source ~= 1 then discard = true end
            if LootLog_looted_items[sorted_items[key]].source == "gargul" and LootLog_source ~= 2 then discard = true end
        end

        -- filter by equippability (hack! scan tooltip for red text color; might break if other addons modify the tooltip)
        scan_frame:ClearLines()
        scan_frame:SetItemByID(item.id)

        local function scan_tooltip(...)
            for i = 1, select("#", ...) do
                local region = select(i, ...)

                if region and region:GetObjectType() == "FontString" then
                    local text = region:GetText()
                    local r, g, b = region:GetTextColor()

                    if text and (r > 0.9 and g < 0.2 and b < 0.2) then
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
                local filter_id = filter_info

                if item.id == filter_id then keep = true end
            end
        end

        if keep and not discard then
            table.insert(shown_items, item)
        end
    end

    if (LootLog_open_on_loot and not loot_frame:IsVisible() and #shown_items ~= loot_frame.field:GetNumItems()) then
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
        ["LeftButton"] = function(item_id)
            if IsShiftKeyDown() then item_to_chat(item_id)
            elseif IsControlKeyDown() then roll_item = item_id; roll_frame:Show()
            else print(loot_information_text(item_id))
            end end
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

-- handle click on an item in the roll window
local event_click_roll = function(mouse_key, item_id)
    local handler = {
        ["LeftButton"] = function(item_id)
            if IsShiftKeyDown() then item_to_chat(item_id)
            else print(loot_information_text(item_id))
            end end
    }

    for item_info, _ in pairs(LootLog_looted_items) do
        if item_info == item_id then
            handler[mouse_key](item_id)
        end
    end
end

local event_roll_timer
event_roll_timer = function()
    local rest = roll_end_time - GetTime()

    roll_frame.announce_roll:Disable()
    roll_frame.duration:Disable()

    if rest > 0.5 then
        C_Timer.After(1, event_roll_timer)
    end

    if rest > 0.5 and rest < 3.5 then
        announce(LootLog_Locale.roll_stop .. " " .. math.floor(rest + 0.5) .. " " .. LootLog_Locale.roll_seconds)
    end

    if rest <= 0.5 then
        announce(LootLog_Locale.roll_stopped)
        roll_started = false
        roll_frame.announce_roll:Enable()
        roll_frame.duration:Enable()

        -- sort list
        local results = roll_frame.results:GetItems()

        table.sort(results, function(a, b)
            if not (a.main_roll == b.main_roll) then
                return a.main_roll
            end

            return a.roll > b.roll
        end)

        roll_frame.results:SetItems(results)
    end
end

local event_addon_loaded = function(_, _, addon)
    if addon == "LootLog" then
        -- options
        if LootLog_frame_visible == nil then
            LootLog_frame_visible = false
        end
        if LootLog_frame_visible then
            loot_frame:Show()
        else
            loot_frame:Hide()
        end

        if LootLog_source == nil then
            LootLog_source = 0
        end

        if LootLog_min_quality == nil then
            LootLog_min_quality = 4
        end

        if LootLog_invertsorting == nil then
            LootLog_invertsorting = true
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

        -- roll settings
        if LootLog_roll_duration == nil then
            LootLog_roll_duration = 10
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
        UIDropDownMenu_SetText(settings_frame.source_options, LootLog_Locale.sources[LootLog_source + 1])

        settings_frame.invertsorting:SetChecked(LootLog_invertsorting)
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

-- function for parsing loot messages
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
        item_cache:getAsync(item_id, function(item) LootLog_looted_items[item.id] = loot_information("loot", 1); update_list() end)
    else
        LootLog_looted_items[item_id] = loot_information("loot", (LootLog_looted_items[item_id]["amount"] and LootLog_looted_items[item_id].amount or 1) + 1)
        update_list()
    end
end

-- function for parsing chat loot messages
local event_gargul = function(_, _, text)
    if text and string.find(text, "Gargul") and string.find(text, "]") and (string.find(text, "]") + 4) == string.len(text) then
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
            item_cache:getAsync(item_id, function(item) LootLog_looted_items[item.id] = loot_information("gargul", 1); update_list() end)
        else
            LootLog_looted_items[item.id] = loot_information("loot", (LootLog_looted_items[item_id]["amount"] and LootLog_looted_items[item_id].amount or 1) + 1)
            update_list()
        end
    end
end

-- function for parsing system chat messages for rolls
local event_rolled = function(_, _, text)
    if roll_started then
        -- find (1-100) for main rolls, (1-50) for off rolls, and ignore rest
        if not text or not (string.find(text, "%(1%-100%)") or string.find(text, "%(1%-50%)")) then
            return
        end

        local main_roll = true

        if text and string.find(text, "%(1%-50%)") then
            main_roll = false
        end

        -- parse message
        text = text:gsub("%(1%-50%)", "")
        text = text:gsub("%(1%-100%)", "")

        local first, last = string.find(text, "[0-9][0-9]*[0-9]*")
        local roll = tonumber(text:sub(first, last))

        local first = string.find(text, " ") - 1
        local player = text:sub(1, first)

        -- update table
        local prior_results = roll_frame.results:GetItems()
        local found = false

        for i, v in ipairs(prior_results) do
            if v.name == player then
                found = true
            end
        end

        if (not found) then
            roll_frame.results:AddItem({name = player, roll = roll, main_roll = main_roll})
        end
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

    loot_frame.info = CreateFrame("Button", "LootLogInfo", loot_frame, "UIPanelInfoButton")
    loot_frame.info:SetPoint("TOPRIGHT", -33, -5)
    loot_frame.info:SetScript("OnEnter", function(_) info_frame:SetPoint("TOPLEFT", loot_frame.info, "BOTTOMRIGHT", 0, 0) info_frame:Show() end)
    loot_frame.info:SetScript("OnLeave", function(_) info_frame:Hide() end)

    loot_frame.close = CreateFrame("Button", "LootLogClose", loot_frame, "UIPanelCloseButton")
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
    loot_frame.settings = CreateButton("LootLogConfig", loot_frame, LootLog_Locale.settings, 100, 25)
    loot_frame.settings:SetPoint("BOTTOMLEFT", 2, 2)

    -- initially hide frame
    loot_frame:Hide()



    -- create item frame for the settings
    local filter_frame = CreateItemFrame("LootLogFilter", settings_frame, 10, 240, event_click_filter)

    -- initialize settings window
    settings_frame:SetFrameStrata("HIGH")
    settings_frame:SetWidth(250)
    settings_frame:SetHeight(223 + select(2, filter_frame:GetFrameSize()))
    settings_frame:SetPoint("LEFT", window_width + 10, 0)
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
    settings_frame.close:SetScript("OnClick", function(_, button) if (button == "LeftButton") then settings_frame:Hide() end end)

    _G["LootLogSettings"] = settings_frame
    tinsert(UISpecialFrames, "LootLogSettings")

    -- filter by source
    local source_y = -30

    settings_frame.source_label = settings_frame:CreateFontString("LootLogSourceLabel", "OVERLAY", "GameFontHighlight")
    settings_frame.source_label:SetPoint("TOPLEFT", 10, source_y - 7)
    settings_frame.source_label:SetText(LootLog_Locale.source)

    settings_frame.source_options = CreateFrame("Frame", "LootLogSourceDropdown", settings_frame, "UIDropDownMenuTemplate")
    settings_frame.source_options:SetPoint("TOPRIGHT", 10, source_y)

    UIDropDownMenu_SetWidth(settings_frame.source_options, 100)
    UIDropDownMenu_Initialize(settings_frame.source_options,
        function(self, _, _)
            local info = UIDropDownMenu_CreateInfo()
            info.func = function(self, arg1, _, _) UIDropDownMenu_SetText(settings_frame.source_options, LootLog_Locale.sources[arg1 + 1]); LootLog_source = arg1; update_list() end

            info.text, info.arg1, info.checked = LootLog_Locale.sources[1], 0, LootLog_source == 0
            UIDropDownMenu_AddButton(info)

            info.text, info.arg1, info.checked = LootLog_Locale.sources[2], 1, LootLog_source == 1
            UIDropDownMenu_AddButton(info)

            info.text, info.arg1, info.checked = LootLog_Locale.sources[3], 2, LootLog_source == 2
            UIDropDownMenu_AddButton(info)
        end)

    -- filter by quality
    local quality_y = -60

    settings_frame.quality_label = settings_frame:CreateFontString("LootLogQualityLabel", "OVERLAY", "GameFontHighlight")
    settings_frame.quality_label:SetPoint("TOPLEFT", 10, quality_y - 7)
    settings_frame.quality_label:SetText(LootLog_Locale.min_quality)

    settings_frame.quality_options = CreateFrame("Frame", "LootLogQualityDropdown", settings_frame, "UIDropDownMenuTemplate")
    settings_frame.quality_options:SetPoint("TOPRIGHT", 10, quality_y)

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

    -- option to invert sorting
    local invertsorting_y = -90

    settings_frame.invertsorting_label = settings_frame:CreateFontString("LootLogInvertSortingLabel", "OVERLAY", "GameFontHighlight")
    settings_frame.invertsorting_label:SetPoint("TOPLEFT", 10, invertsorting_y - 6)
    settings_frame.invertsorting_label:SetText(LootLog_Locale.invertsorting)

    settings_frame.invertsorting = CreateFrame("CheckButton", "LootLogInvertSortingCheckbox", settings_frame, "UICheckButtonTemplate")
    settings_frame.invertsorting:SetSize(25, 25)
    settings_frame.invertsorting:SetPoint("TOPRIGHT", -8, invertsorting_y)
    settings_frame.invertsorting:HookScript("OnClick", function(self, button, ...) LootLog_invertsorting = settings_frame.invertsorting:GetChecked(); update_list() end)

    -- option to show only equippable loot
    local equippable_y = -113

    settings_frame.equippable_label = settings_frame:CreateFontString("LootLogEquippableLabel", "OVERLAY", "GameFontHighlight")
    settings_frame.equippable_label:SetPoint("TOPLEFT", 10, equippable_y - 6)
    settings_frame.equippable_label:SetText(LootLog_Locale.equippable)

    settings_frame.equippable = CreateFrame("CheckButton", "LootLogEquippableCheckbox", settings_frame, "UICheckButtonTemplate")
    settings_frame.equippable:SetSize(25, 25)
    settings_frame.equippable:SetPoint("TOPRIGHT", -8, equippable_y)
    settings_frame.equippable:HookScript("OnClick", function(self, button, ...) LootLog_equippable = settings_frame.equippable:GetChecked(); update_list() end)

    -- option to open frame automatically on new loot
    local auto_open_y = -136

    settings_frame.auto_open_label = settings_frame:CreateFontString("LootLogAutoOpenLabel", "OVERLAY", "GameFontHighlight")
    settings_frame.auto_open_label:SetPoint("TOPLEFT", 10, auto_open_y - 6)
    settings_frame.auto_open_label:SetText(LootLog_Locale.auto_open)

    settings_frame.auto_open = CreateFrame("CheckButton", "LootLogAutoOpenCheckbox", settings_frame, "UICheckButtonTemplate")
    settings_frame.auto_open:SetSize(25, 25)
    settings_frame.auto_open:SetPoint("TOPRIGHT", -8, auto_open_y)
    settings_frame.auto_open:HookScript("OnClick", function(self, button, ...) LootLog_open_on_loot = settings_frame.auto_open:GetChecked() end)

    -- option to add only items to the loot list that are in the following priority list
    local filter_y = -159

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



    -- create information frame
    info_frame:SetFrameStrata("HIGH")
    info_frame:SetWidth(LootLog_Locale.info_width)
    info_frame:SetHeight(75)

    info_frame.background = info_frame:CreateTexture()
    info_frame.background:SetAllPoints(info_frame)
    info_frame.background:SetColorTexture(0.1, 0.1, 0.1, 0.8)

    local info_font = "GameTooltipTextSmall"

    info_frame.left_mouse_label = info_frame:CreateFontString("LootLogInfoLeftMouse", "OVERLAY", info_font)
    info_frame.left_mouse_label:SetPoint("TOPLEFT", 10, -10)
    info_frame.left_mouse_label:SetText(LootLog_Locale.left_mouse)

    info_frame.left_description_label = info_frame:CreateFontString("LootLogInfoLeftDescription", "OVERLAY", info_font)
    info_frame.left_description_label:SetPoint("TOPLEFT", 80, -10)
    info_frame.left_description_label:SetText(LootLog_Locale.left_description)

    info_frame.shift_left_mouse_label = info_frame:CreateFontString("LootLogInfoShiftLeftMouse", "OVERLAY", info_font)
    info_frame.shift_left_mouse_label:SetPoint("TOPLEFT", 10, -25)
    info_frame.shift_left_mouse_label:SetText(LootLog_Locale.shift .. "+" .. LootLog_Locale.left_mouse)

    info_frame.shift_left_description_label = info_frame:CreateFontString("LootLogInfoShiftLeftDescription", "OVERLAY", info_font)
    info_frame.shift_left_description_label:SetPoint("TOPLEFT", 80, -25)
    info_frame.shift_left_description_label:SetText(LootLog_Locale.shift_left_description)

    info_frame.ctrl_left_mouse_label = info_frame:CreateFontString("LootLogInfoCtrlLeftMouse", "OVERLAY", info_font)
    info_frame.ctrl_left_mouse_label:SetPoint("TOPLEFT", 10, -40)
    info_frame.ctrl_left_mouse_label:SetText(LootLog_Locale.ctrl .. "+" .. LootLog_Locale.left_mouse)

    info_frame.ctrl_left_description_label = info_frame:CreateFontString("LootLogInfoCtrlLeftDescription", "OVERLAY", info_font)
    info_frame.ctrl_left_description_label:SetPoint("TOPLEFT", 80, -40)
    info_frame.ctrl_left_description_label:SetText(LootLog_Locale.ctrl_left_description)

    info_frame.right_mouse_label = info_frame:CreateFontString("LootLogInfoRightMouse", "OVERLAY", info_font)
    info_frame.right_mouse_label:SetPoint("TOPLEFT", 10, -55)
    info_frame.right_mouse_label:SetText(LootLog_Locale.right_mouse)

    info_frame.right_description_label = info_frame:CreateFontString("LootLogInfoRightDescription", "OVERLAY", info_font)
    info_frame.right_description_label:SetPoint("TOPLEFT", 80, -55)
    info_frame.right_description_label:SetText(LootLog_Locale.rigth_description)

    -- initially hide frame
    info_frame:Hide()



    -- create item frame
    local roll_item_frame = CreateItemFrame("LootLogRollItem", roll_frame, 1, window_width - 10, event_click_roll)

    -- create roll result frame
    local roll_results_frame = CreateRollFrame("LootLogRollResults", roll_frame, 10, window_width - 10, event_assign_roll)

    -- create roll frame
    roll_frame:SetFrameStrata("HIGH")
    roll_frame:SetPoint("RIGHT", -window_width - 10, 0)
    roll_frame:SetWidth(window_width)
    roll_frame:SetHeight(315)
    roll_frame:SetMovable(true)
    roll_frame:EnableMouse(true)
    roll_frame:RegisterForDrag("LeftButton")
    roll_frame:SetScript("OnDragStart", function(self) self:StartMoving() end)
    roll_frame:SetScript("OnDragStart", function(self) self:StartMoving() end)
    roll_frame:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)
    roll_frame:SetScript("OnShow", function() roll_frame.field:SetItems({item_cache:get(roll_item)}) roll_frame.duration:SetText(LootLog_roll_duration) end)

    roll_frame.background = roll_frame:CreateTexture()
    roll_frame.background:SetAllPoints(roll_frame)
    roll_frame.background:SetColorTexture(0.1, 0.1, 0.1, 0.5)

    roll_frame.title = roll_frame:CreateFontString("LootLogRollTitle", "OVERLAY", "GameFontNormal")
    roll_frame.title:SetPoint("TOPLEFT", 5, -5)
    roll_frame.title:SetText(LootLog_Locale.roll_title)

    roll_frame.close = CreateFrame("Button", "LootLogRollClose", roll_frame, "UIPanelCloseButton")
    roll_frame.close:SetPoint("TOPRIGHT", 0, 2)
    roll_frame.close:SetScript("OnClick", function(_, button) if (button == "LeftButton") then roll_frame:Hide() end end)

    _G["LootLogRollFrame"] = roll_frame
    tinsert(UISpecialFrames, "LootLogRollFrame")

    roll_frame.field = roll_item_frame
    roll_frame.field:SetPoint("TOPLEFT", 5, -25)

    -- roll announcement button
    roll_frame.announce_roll = CreateButton("LootLogRollAnnouncement", roll_frame, LootLog_Locale.roll_announce_roll, 200, 25, function()
        -- announcement
        announce(LootLog_Locale.roll_message .. ": " .. item_cache:get(roll_item).link)

        -- start tracking of rolls
        roll_frame.results:ClearItems()
        roll_started = true

        -- event for regular time events
        roll_end_time = GetTime() + LootLog_roll_duration
        C_Timer.After(0.01, event_roll_timer)
        end)
    roll_frame.announce_roll:SetPoint("TOPLEFT", 2, -50)

    -- roll duration settings
    roll_frame.duration_label = roll_frame:CreateFontString("LootLogDurationLabel", "OVERLAY", "GameFontHighlight")
    roll_frame.duration_label:SetPoint("TOPLEFT", 5, -85)
    roll_frame.duration_label:SetText(LootLog_Locale.roll_duration)

    roll_frame.unit_label = roll_frame:CreateFontString("LootLogUnitLabel", "OVERLAY", "GameFontHighlight")
    roll_frame.unit_label:SetPoint("TOPRIGHT", -5, -85)
    roll_frame.unit_label:SetText(LootLog_Locale.roll_seconds)

    roll_frame.duration = CreateFrame("EditBox", "LootLogDuration", roll_frame)
    roll_frame.duration:SetSize(17, 22)
    roll_frame.duration:SetPoint("TOPLEFT", 115, -80)
    roll_frame.duration:SetFontObject(ChatFontNormal)
    roll_frame.duration:SetAutoFocus(false)
    roll_frame.duration:SetNumeric(true)
    roll_frame.duration:SetText(10)
    roll_frame.duration:SetScript("OnEnterPressed", function(self, ...)
        if tonumber(roll_frame.duration:GetText()) < 2 then roll_frame.duration:SetText(2) end
        if tonumber(roll_frame.duration:GetText()) > 30 then roll_frame.duration:SetText(30) end
        LootLog_roll_duration = tonumber(roll_frame.duration:GetText())
        roll_frame.duration:ClearFocus() end)
    roll_frame.duration:SetScript("OnEscapePressed", function(self, ...)
        roll_frame.duration:SetText(LootLog_roll_duration)
        roll_frame.duration:ClearFocus() end)

    roll_frame.duration.background = roll_frame.duration:CreateTexture()
    roll_frame.duration.background:SetAllPoints(roll_frame.duration)
    roll_frame.duration.background:SetColorTexture(0.5, 0.5, 0.5, 0.5)

    -- list of player rolls
    roll_frame.results = roll_results_frame
    roll_frame.results:SetPoint("TOPLEFT", 5, -110)
    roll_frame.results:ClearItems()

    -- initially hide frame
    roll_frame:Hide()



    -- scripts
    loot_frame.settings:SetScript("OnClick", function(self, ...) if (settings_frame:IsVisible()) then settings_frame:Hide()
        else settings_frame:Show() end;
        UIDropDownMenu_SetText(settings_frame.quality_options, LootLog_Locale.qualities[LootLog_min_quality + 1]);
        UIDropDownMenu_SetText(settings_frame.source_options, LootLog_Locale.sources[LootLog_source + 1]) end)

    scan_frame:SetOwner(WorldFrame, "ANCHOR_NONE")
    scan_frame:AddFontStrings(
        scan_frame:CreateFontString("$parentTextLeft1", nil, "GameTooltipText"),
        scan_frame:CreateFontString("$parentTextRight1", nil, "GameTooltipText"));

    event_load_frame:RegisterEvent("ADDON_LOADED")
    event_load_frame:SetScript("OnEvent", event_addon_loaded)

    event_loot_frame:RegisterEvent("CHAT_MSG_LOOT")
    event_loot_frame:SetScript("OnEvent", event_looted)

    event_gargul_frame:RegisterEvent("CHAT_MSG_RAID_WARNING")
    event_gargul_frame:RegisterEvent("CHAT_MSG_RAID_LEADER")
    event_gargul_frame:RegisterEvent("CHAT_MSG_RAID")
    event_gargul_frame:SetScript("OnEvent", event_gargul)

    event_roll_frame:RegisterEvent("CHAT_MSG_SYSTEM")
    event_roll_frame:SetScript("OnEvent", event_rolled)
end

-- slash commands
SLASH_LOOTLOG1 = "/ll"
SLASH_LOOTLOG2 = "/lootlog"

SlashCmdList["LOOTLOG"] = toggle_visibility
