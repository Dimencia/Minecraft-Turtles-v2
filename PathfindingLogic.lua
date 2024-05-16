-- Logic for pathfinding.  Not really associated with a turtle or anything, just takes in position/orientation/occupiedPositions as arguments when making a path

local Orientations = require("Orientations")
local Extensions = require("Extensions")
local minheap = require("heap")
local logger = require("AdvancedLogging")

local PathfindingLogic = {}

---@class PathfindingSquare : MoveListData
---@field G number
---@field H number
---@field Score number
---@field Weight number
---@field TargetPosition vec3
---@field Parent PathfindingSquare|nil
local PathfindingSquare = { Weight = 1 }

---@class PathfindingSquareParameters
---@field Position vec3
---@field Orientation vec3
---@field TargetPosition vec3
---@field Parent PathfindingSquare|nil


function PathfindingSquare:GetScore()
	return self.G + self.H
end

function PathfindingSquare:GetH()
	return math.abs(self.TargetPosition.x - self.Position.x) + math.abs(self.TargetPosition.y - self.Position.y) + math.abs(self.TargetPosition.z - self.Position.z)
		+ math.abs(self.Orientation:GetNumberOfTurnsTo(self.TargetPosition - self.Position))
end

function PathfindingSquare:GetG()
	local startG = 0
	local parentOrientation = self.Orientation
	if self.Parent then 
		startG = self.Parent.G 
		parentOrientation = self.Parent.Orientation 
	end
	return (startG + (1 + math.abs(parentOrientation:GetNumberOfTurnsTo(self.Orientation)))) * self.Weight
end

function PathfindingSquare:GetOrientationFromParent()
	if not self.Parent then return self.Orientation end
	if self.Parent.Position == self.Position then return self.Parent.Orientation end
	if self.Parent.Position.y ~= self.Position.y then
		return self.Parent.Orientation
	else
		return self.Position - self.Parent.Position
	end
end

function PathfindingSquare:Update()
	self.Orientation = self:GetOrientationFromParent()
	self.G = self:GetG()
	self.H = self:GetH()
	self.Score = self:GetScore()
end

---@return PathfindingSquare
---@param position vec3
---@param orientation vec3
---@param targetPosition vec3
---@param weight integer|nil
---@param parent PathfindingSquare|nil
function PathfindingSquare:new(position, orientation, targetPosition, weight, parent)
    local object = {
		Weight = weight or 1, 
		Position = position, 
		Orientation = orientation, 
		TargetPosition = targetPosition, 
		Parent = parent
	}
	local result = setmetatable(object, {__index = self})
	result:Update()	
	return result
end

-- Given an orientation and a parent square, sets up a new square with a position via the parent's position plus the orientation, and other stuff
---@param currentSquare PathfindingSquare
---@param newPosition vec3
---@param weight integer|nil
function PathfindingSquare:FromParent(currentSquare, newPosition, weight)
	return PathfindingSquare:new(newPosition, currentSquare.Orientation, currentSquare.TargetPosition, weight, currentSquare)
end

			
---@param currentSquare PathfindingSquare
---@param occupiedPositions table<vec3, BlockData>
---@return vec3[]
local function GetAdjacentWalkableSquares(currentSquare, occupiedPositions)
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
local function IsAtOrAdjacentToAny(currentPosition, targetPositions, occupiedPositions)

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
---@param fromPosition vec3
---@param fromOrientation vec3
---@param occupiedPositions table<vec3, BlockData>
---@return MoveListData[]|nil
function PathfindingLogic.GetPath(targetPositions, occupiedPositions, fromPosition, fromOrientation)
	-- The input is 1 or more target positions; ie a chest covering two squares should input two
	-- We'll see if we can use the same H to just the first position, probably fine to sorta 'prioritize' it

	logger:LogDebug("Getting path from position: ", fromPosition, " and orientation ", fromOrientation)

	local targetPosition = targetPositions[1]
	-- Setup an initial square with our own position and orientation
	local currentSquare = PathfindingSquare:new(fromPosition, fromOrientation, targetPosition)
	
	local openList = { } ---@type table<string, PathfindingSquare>
	local closedList = { }---@type table<string, boolean>
	local openHeap = minheap.new()

	local finalMove = nil ---@type MoveListData|nil
	local finalTarget = nil ---@type vec3|nil

	local tickCount = 1

	openList[currentSquare.Position:ToString()] = currentSquare
	openHeap:push(currentSquare, currentSquare.Score)

	repeat 
		-- Get the square with the lowest score
		local currentSquare = openHeap:pop() ---@type PathfindingSquare
		local posString = currentSquare.Position:ToString()

		closedList[posString] = true -- Add this to the closed list, no longer consider it for future moves
		openList[posString] = nil -- Remove from open list
		
		finalTarget = IsAtOrAdjacentToAny(currentSquare.Position, targetPositions, occupiedPositions)
		if finalTarget then -- We found the path target and put it in the list, we're done
			-- If we're not on the finalTarget ourselves, add a new last 'move' to have an Orientation pointing at our target
			if currentSquare.Position ~= finalTarget then
				finalMove = {
					Position = currentSquare.Position,
					Orientation = (finalTarget - currentSquare.Position),
					Parent = currentSquare
				}
			else
                finalMove = currentSquare
            end
			break
		end
		
		local adjacentPositions = GetAdjacentWalkableSquares(currentSquare, occupiedPositions) -- Should never return occupied squares
		for _, position in ipairs(adjacentPositions) do 
			local posString = position:ToString()
			local weight = 1
			if occupiedPositions[posString] and occupiedPositions[posString].IsTurtle then weight = 8 end
			if not closedList[posString] then 
				if not openList[posString] then 
					-- Setup a square with calculated values from the parent
					local aSquare = PathfindingSquare:FromParent(currentSquare, position, weight)
					openList[posString] = aSquare -- Add for consideration in next step
					openHeap:push(aSquare, aSquare.Score)
				elseif openList[posString] then -- square is already in the list, so it already has these params
					local aSquare = openList[posString]
					if currentSquare.G+1 < aSquare.G then
						-- Our path to aSquare is shorter, set the new parent and update the values on the square
						aSquare.Parent = currentSquare
						aSquare:Update()
					end
				end
			end
		end
		tickCount = tickCount + 1
		if tickCount % 1000 == 0 then
			logger:LogDebug("Checking 1000th position " .. currentSquare.Position:ToString() .. " with score " .. currentSquare.Score)
			sleep(0.01) -- Sleep so we're not iterating for too long
		end
	until (not table.hasAnyElements(openList))

	if not finalTarget then
		logger:LogWarning("Exited pathfinding early, finding path failed")
		return nil
	end
	
	local curSquare = finalMove -- Start at the last move, iterate through parents and add them to a list
	local finalMoves = {}
	-- Avoid adding the square without a parent; that's the one we're on already
	while curSquare and curSquare.Parent do
		table.insert(finalMoves, 1, curSquare)
		curSquare = curSquare.Parent
	end

	return finalMoves
end


return PathfindingLogic