local logger = require("AdvancedLogging")
print = logger.Print
local pfData = require("PathfindingTurtle")
Orientations = pfData.Orientations
local vec3 = require("vec3")



-- A harvesting turtle takes in, for a given job: 
-- HarvestableData
--   BlockData -- Type and/or tags of the block to find and interact with... let's start with just a Name
--   IsToolRequired -- If a tool is needed... probably always yes, but idk
--	 Action -- Left or right click with the tool
--	 Products -- Possibly variable amounts
--	 YRange -- Optional, the Y range to look in, min and max (useful for ores)
-- (Note that it doesn't use a lot of that, but the user would define those and we can use the other data later for other things)
-- FuelChest -- vec3
-- ToolChest -- vec3, where to get the tools for its job
-- OutputChest -- vec3, where to store what it gets

-- If it has anything in its inventory that it's dropping off and the output chest is full, it will just wait until it can clear its inventory

local pathfinder = pfData.Builder:new(nil, vec3(-40, 76, 16), Orientations.South)

local harvestData = {
    DiggableTypes = { "minecraft:stone", "minecraft:dirt", "minecraft:grass_block"}
}
local fuelChestPositions = { vec3() }
local toolChestPositions = { vec3() }
local outputChestPositions = { vec3() }

local harvestAreaTopLeft = vec3()
local harvestAreaBottomRight = vec3() -- Defines a bounding box in which it should search/harvest


local fuelConsumedPerBlock = 1
local fuelConsumptionBufferMult = 1.5


local function SelectEmptySlot()
    -- We have 16 slots
    for i=1, 16 do
        if pathfinder.getItemCount(i) == 0 then
            pathfinder.select(i)
            return true
        end
    end
    return false
end

local function Refuel()
    local prevPosition = pathfinder.Position
    local prevOrientation = pathfinder.Orientation
    local prevSelected = pathfinder.getSelectedSlot()
    local limit = pathfinder.getFuelLimit()/2

    pathfinder:MoveTo(fuelChestPositions)

    -- Suck from the inventory and try to refuel with what we suck, until we stop sucking or are fueled
    -- Change our selected slot as necessary when we can't suck anymore, in case it's a different type or our slot is full

    while pathfinder.getFuelLevel() < limit and SelectEmptySlot() do
        pathfinder.suck()
        pathfinder.refuel()
    end

    pathfinder.select(prevSelected)
    pathfinder:MoveTo(prevPosition)
    pathfinder:OrientTo(prevOrientation)
end

local function RefuelIfNeeded()
    local distanceToHome = (fuelChestPositions[1] - pathfinder.Position):len()
    local fuelToHome = fuelConsumedPerBlock * distanceToHome * fuelConsumptionBufferMult
    if pathfinder.getFuelLevel() <= fuelToHome then
        Refuel()
    end
end

local function SuckAll(orientation)
    local method = pathfinder.suck
    if orientation == Orientations.Up then method = pathfinder.suckUp end
    if orientation == Orientations.Down then method = pathfinder.suckDown end
    while SelectEmptySlot() and method() do
    end
end

local function DropAll(orientation)
    local method = pathfinder.drop
    if orientation == Orientations.Up then method = pathfinder.dropUp end
    if orientation == Orientations.Down then method = pathfinder.dropDown end
    for i=1, 16 do
        while pathfinder.getItemCount(i) > 0 and pathfinder.select(i) and method() do
        end
    end
end


local function DigFor(orientation)
    local method = pathfinder.dig
    if orientation == Orientations.Up then method = pathfinder.digUp end
    if orientation == Orientations.Down then method = pathfinder.digDown end
    return method()
end

local function SuckFor(orientation)
    local method = pathfinder.suck
    if orientation == Orientations.Up then method = pathfinder.suckUp end
    if orientation == Orientations.Down then method = pathfinder.suckDown end
    return method()
end


local function DropOffIfNeeded()
    -- We want to be able to path back to face the same direction...
    local prevPosition = pathfinder.Position
    local prevOrientation = pathfinder.Orientation

    -- If we have ... 2 or fewer empty inventory slots, initiate drop off
    -- We don't want to risk not being able to pick up some harvested stuff if they multi drop
    local numEmpty = 0
    for i=1, 16 do
        if pathfinder.getItemCount(i) == 0 then
            numEmpty = numEmpty + 1
            if numEmpty >= 3 then return end
        end
    end

    local orientation = pathfinder:MoveTo(outputChestPositions)
    DropAll(orientation)

    pathfinder:MoveTo(prevPosition)
    pathfinder:OrientTo(prevOrientation)
end

local function GetToolIfNeeded()
    local prevPosition = pathfinder.Position
    local prevOrientation = pathfinder.Orientation

    -- If we don't have a tool in our hand, 
    -- ... which we can only find out by selecting an empty slot, unequipping, checking if anything came out...
    -- which probably takes time... annoying, oh well
    SelectEmptySlot()
    pathfinder.equipRight()
    if pathfinder.getItemCount() > 0 then pathfinder.equipRight() return end -- We have a tool, equip it back and continue

    -- Go to the tool chest
    local orientation = pathfinder:MoveTo(toolChestPositions)
    -- Pull an item and assume it'll be the right one
    local sucked = SuckFor(orientation)
    if not sucked then GetToolIfNeeded() end -- Try again until we suck something

    -- Equip it on the right side
    if not pathfinder.equipRight() then GetToolIfNeeded() end -- If we failed to equip for some reason, just try again with a new empty slot IG

    -- Go back to where you were
    pathfinder:MoveTo(prevPosition)
    pathfinder:OrientTo(prevOrientation)
end




RefuelIfNeeded()

-- The logic should be really simple.  Ignore pathfinding entirely except to move to/from the chests and its last position or start position
-- Start at the top left and iterate your way through the area, mining any mineable blocks you encounter within it
-- If you encounter a block in the way that isn't mineable... then it either has to pathfind, or do some custom logic to 'follow' it by turning left or whatever

-- Hmm... maybe not.  Maybe it pathfinds to the nearest undiscovered block, if none are discovered which are mineable
--   This would always be pathable unless it's legitimately unreachable; usually it would reveal a mineable block that it can then mine and go again

-- I also then don't have to like, track what I've seen already, it's all part of pathfinding

-- I do kinda wish I store pathfinding info in a more iterable way now, but it's fine



local function vectorToString(vec)
	if not vec then return "ERROR: vec was null..." end
	return vec.x .. "," .. vec.y .. "," .. vec.z
end

function table.contains(table, element)
    for _, value in pairs(table) do
      if value == element then
        return true
      end
    end
    return false
  end

local function DoHarvest()
    -- Iterate all of X, Y, Z in the harvest area

    for x=harvestAreaTopLeft.x, harvestAreaBottomRight.x do
        for y=harvestAreaTopLeft.y, harvestAreaBottomRight.y do
            for z=harvestAreaTopLeft.z, harvestAreaBottomRight.z do
                -- If we need to refuel, do so and return and continue
                RefuelIfNeeded()
                -- If our inventory is full or nearly full, drop off and then continue
                DropOffIfNeeded()
                -- If we don't have a tool, try to get/equip one from the tool chest
                GetToolIfNeeded()
                
                local targetBlock = vec3(x,y,z)
                -- If this block is known and is not diggable, do nothing
                local blockData = pathfinder.OccupiedPositions[vectorToString(targetBlock)]
                -- If it's unknown, path to it to reveal it
                if not blockData then
                    pathfinder:MoveTo(targetBlock)
                    blockData = pathfinder.OccupiedPositions[vectorToString(targetBlock)]
                end

                -- If it's known and diggable, path to it and dig it
                if blockData and blockData.Name and table.contains(harvestData.DiggableTypes, blockData.Name) then
                    local orientation = pathfinder:MoveTo(targetBlock)
                    DigFor(orientation) -- TODO: Make sure dig updates stuff afterward in pathfinding
                    -- And pick up anything it dropped... TODO, maybe do this better somehow, I think it can sometimes end up in a different place
                    SuckFor(orientation)
                end
                

                -- If pathing fails (timeout because it's unreachable, I guess blockData would be nil), continue and do nothing
            end
        end
    end
end

DoHarvest()