ItemCache = {}
ItemCache.queue = {}
ItemCache.cache = {}
ItemCache.event_frame = nil

function ItemCache.new()
    local itemCache = {}
    setmetatable(itemCache, ItemCache)
    ItemCache.__index = ItemCache

    itemCache.event_frame = CreateFrame("Frame")
    itemCache.event_frame:RegisterEvent("GET_ITEM_INFO_RECEIVED")
    itemCache.event_frame:SetScript("OnEvent", function(_, _, item_id, success) itemCache:event(item_id, success) end)

    return itemCache
end

function ItemCache:getAsync(item_id, callback_func)
    local item_id = type(item_id) == "string" and tonumber(item_id) or item_id

    if self.cache[item_id] then
        callback_func(self.cache[item_id])
    else
        if not self.queue[item_id] then
            self.queue[item_id] = {id = item_id, funcs = {callback_func}}
        else
            table.insert(self.queue[item_id].funcs, callback_func)
        end

        if GetItemInfo(item_id) then
            self:event(item_id, true)
        end
    end
end

function ItemCache:get(item_id)
    local item_id = type(item_id) == "string" and tonumber(item_id) or item_id

    return self.cache[item_id]
end

function ItemCache:loaded()
    return next(self.queue) == nil
end

function ItemCache:event(item_id, success)
    local item_id = type(item_id) == "string" and tonumber(item_id) or item_id

    -- check if the item that triggered the event is available
    if self.queue[item_id] then
        if success then
            self.cache[item_id] =
            {
                id = item_id,
                name = C_Item.GetItemNameByID(item_id),
                quality = C_Item.GetItemQualityByID(item_id)
            }

            for _, func in ipairs(self.queue[item_id].funcs) do
                func(self.cache[item_id])
            end
        end

        self.queue[item_id] = nil
    end
end

return ItemCache
