local logger = require("AdvancedLogging")
print = logger.Print

local pfData = require("PathfindingTurtle")
Orientations = pfData.Orientations

--pfData.Tests.Run_All_Tests()

local vec3 = require("vec3")

local pathfinder = pfData.Builder:new(nil, vec3(-40, 76, 16), Orientations.South)

-- Assume that I'm going to place and start it when it's infront of a refueling chest or with fuel in inventory...
-- Intentionally put these positions ontop of a chest so it can turn to face it from wherever it happens to get near it
local sourceChestPositions = {
    vec3(-40, 76, 17),
    vec3(-39, 76, 17),
}


-- Each chest position can allow multiple names for the same quantity, or multiple different ones... 
local itemChests = {
    {
        -- Fuel chest for logs
        ChestPositions = {
            vec3(-39, 75, 13),
            vec3(-40, 75, 13)
        },
        Filter = "*log",
        DesiredQuantity = nil -- Anything more than DesiredQuantity in the destination will overflow
    },
    {
        -- Stick chest for testing
        ChestPositions = {
            vec3(-48, 77, 16),
            vec3(-49, 77, 16)
        },
        Filter = "*stick",
        DesiredQuantity = 256
    },
    {
        -- Another random chest for overflow, which in my case will feed back to source
        ChestPositions = {
            vec3(-46, 76, 17),
            vec3(-47, 76, 17) 
        },
        Filter = "*"
        
    }
}

local refuelChestPositions = {
    vec3(-39, 75, 13),
    vec3(-40, 75, 13)
}

-- We're going to dedicate one slot for fueling, which should never be filled in any circumstances otherwise
-- When taking from a fuel chest, if we get an item that isn't fuel, we're going to drop it... just arbitrarily to the 'right' of where we're standing
local fuelSlot = 16

-- Because there's no good way to check what's in the source or put things in specific places, 
-- We have to assume we're emptying the source, no matter what's in it.  There should prob always be a * chest
-- Unless you want stuff stuck in the turtle (I'm not gonna try putting it back in, for now)



function string:starts_with(start)
    return self:sub(1, #start) == start
 end
 
function string:ends_with(ending)
    return ending == "" or self:sub(-#ending) == ending
end

function string:containsWildcard(wildcard)
    local result = wildcard == "*" or (self == wildcard or (wildcard:starts_with("*") and self:ends_with(wildcard:sub(2, #wildcard))))
    return result
end

local function ManageInventory()
    -- Combines stacks

    -- Make a collection with info about any non-full slots; we don't care about full ones except to move them from reserved
    -- We'll key it by name
    local partialSlots = {}
    for i=1, 16 do
        local detail = pathfinder.getItemDetail(i)
        if detail and pathfinder.getItemSpace(i) > 0 then
            -- If we have another partial slot with the same name, go ahead and try to combine them
            if partialSlots[detail.name] then
                pathfinder.select(i)
                pathfinder.transferTo(partialSlots[detail.Name])
                -- If the partial slot is now full, remove it
                if pathfinder.getItemSpace(partialSlots[detail.Name]) == 0 then
                    partialSlots[detail.Name] = nil
                end
                -- If our slot is not full or empty, set it; this should only occur if we already removed the previous
                if pathfinder.getItemSpace(i) > 0 and pathfinder.getItemDetail(i) then
                    partialSlots[detail.name] = i
                end
            end
        end
    end
end


local function SelectEmptySlot()
    -- We have 16 slots, ignore the fuel slot
    for i=1, 16 do
        if i ~= fuelSlot and pathfinder.getItemCount(i) == 0 then
            pathfinder.select(i)
            return true
        end
    end
    return false
end




local function MethodFor(methodName, orientation, param)
    -- We can sorta cheese this, in that if you give me 'suck', I can append Up or Down and return the method on the turtle
    if orientation == Orientations.Up then methodName = methodName .. "Up" end
    if orientation == Orientations.Down then methodName = methodName .. "Down" end
    return pathfinder[methodName](param)
end

local function SuckFor(orientation)
    return MethodFor("suck", orientation)
end

local function DropFor(orientation, amount)
    return MethodFor("drop", orientation, amount)
end

-- Trying to catch-all any situation so this always can get the job done, 
-- This does mean that in some rare cases, it will be dropping items to its right while pulling from fuel chest, 
-- If the fuel chest contains non-fuel items and its inventory is otherwise full
local function Refuel()

    local limit = pathfinder.getFuelLimit()/2
    -- Try to refuel from inventory first... for cases where we're starting with 0 fuel and not at a chest
    if pathfinder.getItemCount(fuelSlot) > 0 then
        pathfinder.select(fuelSlot)
        pathfinder.refuel() -- Don't drop it yet if it's bad fuel, we'll do that once we're at the chest so it's not everywhere
        if pathfinder.getFuelLevel >= limit then return end
    end
    -- Even if our fuel slot was empty, if we're at 0 we can still try all other slots.  If not, use the chest
    --   so we can try to guarantee it doesn't use fuel that we might not want turtles to use
    if pathfinder.getFuelLevel() == 0 then
        print("Completely out of fuel, trying from inventory")
        for i=1, 16 do
            if pathfinder.getItemCount(i) == 0 then
                pathfinder.select(i)
                pathfinder.refuel()
                if pathfinder.getFuelLevel >= limit then return end
            end
        end
    end

    -- If we've checked every slot and we're still not above our limit, find the fuel chest
    local prevPosition = pathfinder.Position
    local prevOrientation = pathfinder.Orientation
    local chestOrientation = pathfinder:MoveTo(refuelChestPositions)

    -- Suck from the inventory and try to refuel with what we suck, until we stop sucking or are fueled
    while SelectEmptySlot() and pathfinder.getFuelLevel() < limit do
        SuckFor(chestOrientation)
        pathfinder.refuel()
    end

    -- If our inventory is full, it's possible we haven't yet iterated it for fuel, so try that first
    if not SelectEmptySlot() and pathfinder.getFuelLevel() < limit then
        for i=1, 16 do
            if pathfinder.getItemCount(i) == 0 then
                pathfinder.select(i)
                pathfinder.refuel()
                if pathfinder.getFuelLevel >= limit then return end
            end
        end
    end

    -- If our inventory is full (other than fuelSlot) and we're still not at limit, none of it is fuel,
    -- So now we have to use fuelSlot and drop it if we suck non-fuel
    if not SelectEmptySlot() and pathfinder.getFuelLevel() < limit then
        pathfinder.select(fuelSlot)
        while pathfinder.getFuelLevel() < limit do
            SuckFor(chestOrientation)
            if not pathfinder.refuel() then -- If not valid fuel, drop it arbitrarily to the right somewhere
                pathfinder.turnRight()
                pathfinder.drop()
                pathfinder.turnLeft()
            end
        end
    end

    -- If we get out of this loop, we're fueled and can go back home
    -- If there is no fuel in the chest, it'll keep trying til there is, 
    -- And if there's non-fuel in the chest or fuel slot, it'll keep dropping it and trying again

    pathfinder:MoveTo(prevPosition)
    pathfinder:OrientTo(prevOrientation)
end


local function RefuelIfNeeded()
    if pathfinder.getFuelLevel() <= pathfinder.getFuelLimit()/2 then
        Refuel()
    end
end

local function SuckAll(orientation)
    local suckedAny = false
    while SelectEmptySlot() and SuckFor(orientation) do
        suckedAny = true
    end

    if suckedAny then
        ManageInventory() -- Combine items as needed
        -- Then try to suck again to make sure we can't fit more now
        SuckAll(orientation)
        return true -- But we did suck already
    end

    return suckedAny
end

local function WrapChestIn(orientation)
    local name = "front"
    if orientation == Orientations.Up then name = "top"
    elseif orientation == Orientations.Down then name = "bottom" end
    return peripheral.wrap(name)
end

local function CountItems(orientation, chestData)
    local count = 0
    local chest = WrapChestIn(orientation)
    if chest then
        local items = chest.list()
        for k,v in pairs(items) do
            if v.name and v.count and v.count > 0 and (not chestData or not chestData.Filter or v.name:containsWildcard(chestData.Filter)) then
                count = count + v.count
            end
        end
    end
    return count
end

local function DropAll(orientation, chestData)
    for i=1, 16 do
        if i ~= fuelSlot then
            local detail = pathfinder.getItemDetail(i)
            if detail and (not chestData or not chestData.Filter or (detail.name and chestData.Filter and detail.name:containsWildcard(chestData.Filter))) then
                -- Check if it has enough or if we need to add more
                local numToTransfer = detail.count
                if chestData.DesiredQuantity then
                    -- Drop will error if it's bigger than count or stack size, so account for that here
                    numToTransfer = math.min(detail.count, math.max(chestData.DesiredQuantity - CountItems(orientation, chestData), 0))
                end
                if not numToTransfer or numToTransfer > 0 then
                    pathfinder.select(i)
                    DropFor(orientation, numToTransfer)
                end
            end
        end
    end
end

RefuelIfNeeded()

while true do
    local orientation = pathfinder:MoveTo(sourceChestPositions)

    local suckedAny = SuckAll(orientation)
    if suckedAny then
        -- Iterate item chests and see if we have any items for each one in order
        -- Overflow will hit the last wildcard naturally, assuming there is one
        for _,chest in ipairs(itemChests) do
            for i=1, 16 do
                if i ~= fuelSlot then
                    local detail = pathfinder.getItemDetail(i)
                    if detail and detail.name and (not chest.Filter or detail.name:containsWildcard(chest.Filter)) then
                        -- We have an item in our list, go to that chest and drop off
                        orientation = pathfinder:MoveTo(chest.ChestPositions)
                        DropAll(orientation, chest)
                        RefuelIfNeeded() -- They could be far away, so check refuel between each chest
                    end
                end
            end
        end
    end
    -- Refresh server path data
    pathfinder:GetServerPathData()
end