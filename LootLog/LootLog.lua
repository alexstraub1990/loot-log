-- user settings
local window_width = 200
local num_items = 15

-- top-level gui frames
local loot_frame = CreateFrame("Frame", "LootLogFrame", UIParent)

local settings_frame = CreateFrame("Frame", "LootLogSettings", UIParent)
local settings_frame_visible = false

-- settings
local qualities = {"Poor", "Common", "Uncommon", "Rare", "Epic", "Legendary"}

-- toggle gui visibility
local toggle_visibility = function(self, _)
    if (LootLog_frame_visible) then
        loot_frame:Hide()
        LootLog_frame_visible = false
    else
        loot_frame:Show()
        LootLog_frame_visible = true
    end
end

-- update shown list
local update_list = function()
    if (LootLog_looted_items == nil) then return end

    shown_items = {}

    for _, item_info in ipairs(LootLog_looted_items) do
        local item = {}
        item.id = item_info[1]
        item.name = item_info[2]
        item.quality = item_info[3]
        
        -- TODO: filter by quality, equipability, maybe stats?
        discard = false
        
        if (item.quality < LootLog_min_quality) then discard = true end
        
        -- add ID, icon, text color, and item name
        if (not discard) then
            table.insert(shown_items, item)
        end
    end
    
    loot_frame.field:SetItems(shown_items)
end

-- handle click on an item
local event_click_item = function(mouse_key, item_id)
    if (mouse_key == "LeftButton") then
        -- TODO: maybe lock the item?
    elseif (mouse_key == "RightButton") then
        for i, item_info in ipairs(LootLog_looted_items) do
            if (item_info[1] == item_id) then
                table.remove(LootLog_looted_items, i)
            end
        end
    end
    
    update_list()
end

-- load stored values
local event_addon_loaded = function(self, event, addon)
    if addon == "LootLog" then
        if LootLog_looted_items == nil then
            LootLog_looted_items = {}
        end
        
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
        
        if LootLog_minimap == nil then
            LootLog_minimap = {
                ["minimapPos"] = 200.0,
                ["hide"] = false,
            }
        end
        
        -- minimap button
        local miniButton = LibStub("LibDataBroker-1.1"):NewDataObject("LootLog", {
            type = "data source",
            text = "Loot Log",
            icon = "Interface\\HELPFRAME\\HelpIcon-KnowledgeBase",
            OnClick = function(self, _) toggle_visibility(self, nil) end,
            OnTooltipShow = function(tooltip) if not tooltip or not tooltip.AddLine then return end; tooltip:AddLine("Loot Log") end,
        })

        local icon = LibStub("LibDBIcon-1.0", true)
        icon:Register("LootLog", miniButton, LootLog_minimap)
        
        -- intially update list
        update_list()
    end
end

-- main function for parsing loot messages
local event_looted = function(self, event, text, ...)
    -- parse item information
    _, item_id_start = string.find(text, "|Hitem:")
    text = string.sub(text, item_id_start + 1, -1)
    
    item_id_end, _ = string.find(text, ":")
    text = string.sub(text, 1, item_id_end - 1)
    
    item_id = text
    item_name = C_Item.GetItemNameByID(item_id)
    item_quality = C_Item.GetItemQualityByID(item_id)
    
    -- show and fill frame
    found = false
    
    for _, item_info in ipairs(LootLog_looted_items) do
        if (item_info[1] == item_id) then found = true end
    end
    
    if (not found) then
        table.insert(LootLog_looted_items, {item_id, item_name, item_quality})
    end
    
    update_list()
end

-- create events
local event_load_frame = CreateFrame("Frame")
event_load_frame:RegisterEvent("ADDON_LOADED")
event_load_frame:SetScript("OnEvent", event_addon_loaded)

local event_loot_frame = CreateFrame("Frame")
event_loot_frame:RegisterEvent("CHAT_MSG_LOOT")
event_loot_frame:SetScript("OnEvent", event_looted)

-- initialize frame
local init = function()
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
    loot_frame.title:SetText("Loot Log")

    loot_frame.field = item_frame
    loot_frame.field:SetPoint("TOPLEFT", 5, -25)
    
    -- roll 100 button
    loot_frame.roll_main = CreateButton("LootLogRoll100", loot_frame, "Roll 100", 100, 25, function(self, ...) RandomRoll(1, 100) end)
    loot_frame.roll_main:SetPoint("BOTTOMLEFT", 2, 27)

    -- roll 50 button
    loot_frame.roll_off = CreateButton("LootLogRoll50", loot_frame, "Roll 50", 100, 25, function(self, ...) RandomRoll(1, 50) end)
    loot_frame.roll_off:SetPoint("BOTTOMRIGHT", -2, 27)

    -- clear button
    loot_frame.clear = CreateButton("LootLogClear", loot_frame, "Clear", 100, 25, function(self, ...) for i = #LootLog_looted_items, 1, -1 do table.remove(LootLog_looted_items, i) end; update_list() end)
    loot_frame.clear:SetPoint("BOTTOMRIGHT", -2, 2)

    -- settings button
    loot_frame.settings = CreateButton("LootLogSettings", loot_frame, "Settings", 100, 25)
    loot_frame.settings:SetPoint("BOTTOMLEFT", 2, 2)
    
    -- initially hide frame
    loot_frame:Hide()
    
    
    
    -- initialize settings window
    settings_frame:SetFrameStrata("HIGH")
    settings_frame:SetWidth(250)
    settings_frame:SetHeight(100)
    settings_frame:SetPoint("CENTER", -300, 0)
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
    settings_frame.title:SetText("Loot Log — Settings")
    
    -- filter by quality
    settings_frame.quality_label = settings_frame:CreateFontString("LootLogQualityLabel", "OVERLAY", "GameFontHighlight")
    settings_frame.quality_label:SetPoint("TOPLEFT", 10, -37)
    settings_frame.quality_label:SetText("Min. quality")
    
    settings_frame.quality_options = CreateFrame("Frame", "LootLogQualityLabel", settings_frame, "UIDropDownMenuTemplate")
    settings_frame.quality_options:SetPoint("TOPRIGHT", 5, -30)
    
    UIDropDownMenu_SetWidth(settings_frame.quality_options, 100)
    UIDropDownMenu_Initialize(settings_frame.quality_options,
        function(self, _, _)
            local info = UIDropDownMenu_CreateInfo()
            info.func = function(self, arg1, _, _) UIDropDownMenu_SetText(settings_frame.quality_options, qualities[arg1 + 1]); LootLog_min_quality = arg1; update_list() end
            
            info.text, info.arg1, info.checked = qualities[1], 0, LootLog_min_quality == 0
            UIDropDownMenu_AddButton(info)
            
            info.text, info.arg1, info.checked = qualities[2], 1, LootLog_min_quality == 1
            UIDropDownMenu_AddButton(info)
            
            info.text, info.arg1, info.checked = qualities[3], 2, LootLog_min_quality == 2
            UIDropDownMenu_AddButton(info)
            
            info.text, info.arg1, info.checked = qualities[4], 3, LootLog_min_quality == 3
            UIDropDownMenu_AddButton(info)
            
            info.text, info.arg1, info.checked = qualities[5], 4, LootLog_min_quality == 4
            UIDropDownMenu_AddButton(info)
            
            info.text, info.arg1, info.checked = qualities[6], 5, LootLog_min_quality == 5
            UIDropDownMenu_AddButton(info)
            
            if (not (LootLog_min_quality == nil)) then
                UIDropDownMenu_SetText(settings_frame.quality_options, qualities[LootLog_min_quality + 1])
            end
        end)
    
    settings_frame:Hide()
    
    
    
    -- button scripts
    loot_frame.settings:SetScript("OnClick", function(self, ...) if (settings_frame_visible) then settings_frame_visible = false; settings_frame:Hide() else settings_frame_visible = true; settings_frame:Show() end; UIDropDownMenu_SetText(settings_frame.quality_options, qualities[LootLog_min_quality + 1]) end)
end

init()

-- slash commands
SLASH_LOOTLOG1 = "/ll"
SLASH_LOOTLOG2 = "/lootlog"

SlashCmdList["LOOTLOG"] = toggle_visibility
