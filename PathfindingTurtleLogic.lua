-- This is a rednet-wrapped turtle, for use by the server, with methods for pathfinding built into it

-- I mean, at this point it's just the pathfinding methods, and tbh can probably be abstracted separately from the rednet part

-- I think the rednet piece will extend this



local Orientations = require("Orientations")
local Extensions = require("Extensions")
local json = require("json")
local minheap = require("heap")
local BlockData, PositionData, MoveListData, MoveListResult, DirectionDefinition, TurtleRednetMessage = table.unpack(require("PathfindingTurtleBase"))
local vec3 = require("vec3")

---@class PathfindingTurtleLogic : PathfindingTurtleNetworkMethods
---@field Position vec3
---@field Orientation vec3
local PathfindingTurtleLogic = { Position = vec3(), Orientation = vec3()}

---@return PathfindingTurtleLogic
---@param values PathfindingTurtleLogic
function PathfindingTurtleLogic:new(values)
	self.__index = self
    return setmetatable(values or {}, self)
end




---@class PathfindingSquare : MoveListData
---@field G number
---@field H number
---@field Score number
---@field Weight number

local PathfindingSquare = MoveListData:new()
---@return PathfindingSquare
---@param values PathfindingSquare
function PathfindingSquare:new(values)
	self.__index = self
    return setmetatable(values or MoveListData:new(), self)
end



-- Pathfinding
---@param position vec3
---@param orientation vec3
---@param targetPosition vec3
---@return number
function PathfindingTurtleLogic:GetH(position, orientation, targetPosition)
	-- We'll be exact and explicit; the way we pathfind, the distance from any square in a 'straight line'
	-- is each of x,y,z distance plus number of turns
	return math.abs(targetPosition.x - position.x) + math.abs(targetPosition.y - position.y) + math.abs(targetPosition.z - position.z)
		+ math.abs(orientation:GetNumberOfTurnsTo(targetPosition - position))
end

---@param adjacentSquare PathfindingSquare
---@param currentSquare PathfindingSquare
---@param targetPosition vec3
---@return PathfindingSquare
function PathfindingTurtleLogic:ComputeSquare(adjacentSquare, currentSquare, targetPosition)
	local result = adjacentSquare
	-- Build an orientation, for:
	-- 1. Calculating the cost of turning, 
	-- 2. Being able to orient to face a target once we've reached the end

	-- Note that this is the orientation to get to our position, because currentSquare may have multiple next positions
	if currentSquare.Position.y ~= adjacentSquare.Position.y then
		result.Orientation = currentSquare.Orientation
	else
		result.Orientation = adjacentSquare.Position - currentSquare.Position
	end
	result.Position = adjacentSquare.Position
	result.Parent = currentSquare
	-- Add 1 to move, and any orientation change takes as long as a move, so consider those
	-- Weight was set previously based mostly on whether it was a turtle or not
	result.G = (currentSquare.G + (1 + math.abs(currentSquare.Orientation:GetNumberOfTurnsTo(result.Orientation)))) * (result.Weight or 1)
	result.H = self:GetH(result.Position, result.Orientation, targetPosition)
	result.Score = result.G + result.H
	return result
end
			
---@param currentSquare PathfindingSquare
---@param occupiedPositions table<vec3, BlockData>
---@return vec3[]
function PathfindingTurtleLogic:GetAdjacentWalkableSquares(currentSquare, occupiedPositions)
	local results = {}
	for k,v in pairs(Orientations) do
		local targetVec = currentSquare.Position + v
		local blockData = occupiedPositions[targetVec:ToString()]
		-- We allow it to try to traverse unexplored blocks, otherwise it can never get started
		if (not blockData) or (not blockData.IsOccupied) then
			results[#results + 1] = targetVec
		end
	end
	return results
end

-- Returns the target position it's at or adjacent to, or nil if none
---@param currentPosition vec3
---@param targetPositions vec3[]
---@param occupiedPositions table<vec3, BlockData>
---@return vec3|nil
function PathfindingTurtleLogic:IsAtOrAdjacentToAny(currentPosition, targetPositions, occupiedPositions)

	-- First we should check if any of them are equal; we wouldn't want to exit early if any are actually accessible
	for k,targetPosition in ipairs(targetPositions) do
		if currentPosition == targetPosition then return targetPosition end
	end
    
	 -- Accept one space away otherwise
	for k,targetPosition in ipairs(targetPositions) do
		local targetData = occupiedPositions[targetPosition:ToString()]
		if targetData and targetData.IsOccupied and 
			(currentPosition.x == targetPosition.x or currentPosition.z == targetPosition.z or currentPosition.y == targetPosition.y)
				and (currentPosition-targetPosition):len() == 1 then
					return targetPosition
				end
	end
	return nil
end

-- Returns true/false if it successfully pathed, and the path, possibly including a final position that is just reorienting
-- Note: We accept target positions that may be occupied, in which case we'll path to an adjacent square
---@param targetPositions vec3[]
---@param fromPosition vec3|nil
---@param fromOrientation vec3|nil
---@param occupiedPositions table<vec3, BlockData>
---@return MoveListData[]|nil
function PathfindingTurtleLogic:GetPath(targetPositions, occupiedPositions, fromPosition, fromOrientation)
	-- The input is 1 or more target positions; ie a chest covering two squares should input two
	-- We'll see if we can use the same H to just the first position, probably fine to sorta 'prioritize' it
	
	if not fromPosition then fromPosition = self.Position end
	if not fromOrientation then fromOrientation = self.Orientation end

	print("Getting path from position: ", fromPosition, " and orientation ", fromOrientation)

	local targetPosition = targetPositions[1]
	-- Let's setup an initial square with our own position and orientation
	local initialSquare = PathfindingSquare:new {
		Position = fromPosition,
		Orientation = fromOrientation,
		H = self:GetH(fromPosition, fromOrientation, targetPosition),
		G = 0
	}
	initialSquare.Score = initialSquare.H + initialSquare.G

	local currentSquare = initialSquare
	
	local openList = { } -- A map of position vector to Square
	openList[currentSquare.Position:ToString()] = currentSquare
	local openHeap = minheap.new()
	openHeap:push(currentSquare, currentSquare.Score)
	local closedList = {}
	
	local tickCount = 1
	
	local finalMove = nil
	local finalTarget = nil
	repeat 
		-- Get the square with the lowest score
		local currentSquare = openHeap:pop()
		
		local posString = currentSquare.Position:ToString()
		-- Add this to the closed list, no longer consider it for future moves
		closedList[posString] = true
		openList[posString] = nil -- Remove from open list
		
		finalTarget = self:IsAtOrAdjacentToAny(currentSquare.Position, targetPositions, occupiedPositions)
		if finalTarget then
			-- We found the path target and put it in the list, we're done. 

			-- If we're not on the finalTarget, add a new last 'move' to have an Orientation pointing at our target
			if currentSquare.Position ~= finalTarget then
				finalMove = MoveListData:new {
					Position = currentSquare.Position,
					Orientation = (finalTarget - currentSquare.Position),
					Parent = currentSquare
				}
			else
                finalMove = currentSquare
            end
			break
		end
		
		local adjacentSquares = self:GetAdjacentWalkableSquares(currentSquare, occupiedPositions) -- Should never return occupied squares
		-- Returns us a list where the keys are positions, and values have data like IsOccupied
		for _, position in ipairs(adjacentSquares) do 
			local posString = position:ToString()
            local aSquare = PathfindingSquare:new { Position = position, Weight = 1 }
			if occupiedPositions[posString] and occupiedPositions[posString].IsTurtle then aSquare.Weight = 8 end
			if not closedList[posString] then 
				if not openList[posString] then 
					-- Compute G, H, and F, and set them on the square
					self:ComputeSquare(aSquare, currentSquare, targetPosition)
					-- Add for consideration in next step
					openList[posString] = aSquare
					openHeap:push(aSquare, aSquare.Score)
				elseif openList[posString] then -- aSquare is already in the list, so it already has these params
					aSquare = openList[posString] -- Use the existing object
					if currentSquare.G+1 < aSquare.G then
						-- Our path to aSquare is shorter, use our values, replaced into the object - which is already in the heap and list
						self:ComputeSquare(aSquare, currentSquare, targetPosition)
					end
				end
			end
		end
		tickCount = tickCount + 1
		if tickCount % 1000 == 0 then
			print("Checking 1000th position " .. currentSquare.Position:ToString() .. " with score " .. currentSquare.Score)
			sleep(0.1)
		end
	until (not table.hasAnyElements(openList))

	if not finalTarget then
		print("Exited pathfinding early... returning false")
		return nil
	end
	
	local curSquare = finalMove -- We set this above when we found it, start at the end
	-- Each one gets inserted in front of the previous one
	local finalMoves = {}
	-- Avoid adding the square without a parent; that's the one we're on
	while curSquare and curSquare.Parent do
		-- and (curSquare.Position.x ~= fromPosition.x and curSquare.Position.y ~= fromPosition.y and curSquare.Position.z ~= fromPosition.z) do
		table.insert(finalMoves, 1, curSquare)
		curSquare = curSquare.Parent
	end

	return finalMoves
end


return PathfindingTurtleLogic