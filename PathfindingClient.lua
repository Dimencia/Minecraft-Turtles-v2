-- A simple pathfinding turtle client, capable of following a list of moves from a pathfinding server and returning block data it detected
local Extensions = require("Extensions")
local Orientations = require("Orientations")
-- TODO: Store and load these from some sub folder?  So they're not in the way making a mess of the files on the turtle
local vec3 = require("vec3")
local json = require("json")
local logger = require("AdvancedLogging")
local wrapModule = require("RednetWrappable")

logger:AddLogger(print, LogLevels.Debug)
logger:AddFileLogger("LogFile", LogLevels.Warning)

-- Class for the turtle's state, which is sent with every rednet message when accessed as a wrappable
---@class TurtleState
---@field Position vec3
---@field Orientation vec3
---@field CurrentVersion string

-- Class for a turtle client, exposing methods to be called via rednet
---@class PathfindingClient : RednetWrapClient
---@field private Position vec3
---@field private Orientation vec3
---@field private CurrentVersion string
local Client = wrapModule.ClientBuilder.new(turtle) -- Start from turtle, which metas to wrapclient, which metas to the static

Client.Id = os.getComputerID() ---@private
Client.FuelSlot = 16 ---@private
Client.HostedProtocolName = Extensions.TurtleClientProtocol
---@private
---@type table<string, BlockData>
Client.BlockData = {}


-- Private client methods

-- When a turtle is in front, above, or below us, we can wrap it and get its ID
---@private
function Client:GetAdjacentComputerId(orientation)
	local wrapDirection = "front"
	if orientation == Orientations.Down then wrapDirection = "bottom" end
	if orientation == Orientations.Up then wrapDirection = "top" end
	local wrapped = peripheral.wrap(wrapDirection)
	if wrapped and wrapped.getID then
		return wrapped.getID()
	end
	return nil
end

---@class TurtleBlockDetails
---@field name string

---@private
---@return BlockData
---@param orientation vec3
function Client:SetBlockData(orientation)
	local methodName = Extensions.GetMethodNameFor("inspect", orientation)
	local isOccupied, data = self[methodName]()
	local position = self.Position + orientation
	local result = BlockData:new {
		Position = position,
		IsOccupied = isOccupied,
		Name = data.name,
		ComputerId = self:GetAdjacentComputerId(orientation)
	}
	self.BlockData[position:ToString()] = result
	return result
end

---@private
function Client:DetectBlocks()
	-- Detects all blocks and stores the data
	self:SetBlockData(self.Orientation)
	self:SetBlockData(Orientations.Up)
	self:SetBlockData(Orientations.Down)
end

-- A little weird, but centralizes the logic for moving in a sorta generic way
---@private
---@param directionDefinition DirectionDefinition
---@return boolean, string|nil
function Client:PerformMovement(directionDefinition)
	self:DetectBlocks()
	local result, reason = directionDefinition.BaseMethod()

	if result then
		if directionDefinition.PositionChange then
			local change = directionDefinition.PositionChange()
			if change then
				self.Position = self.Position + change
			end
		end
		if directionDefinition.RotationChange then
			self.Orientation = self.Orientation:Turn(directionDefinition.RotationChange)
		end
	end
	
	self:DetectBlocks()
	return result, reason
end

---@private
function Client:SetupMovementDirections()

	local directions = {
		forward = { PositionChange = function() return self.Orientation end },
		back = { PositionChange = function() return -self.Orientation end },
		up = { PositionChange = function() return Orientations.Up end },
		down = { PositionChange = function() return Orientations.Down end },
		turnLeft = { RotationChange = -1 },
		turnRight = { RotationChange = 1 },
		dig = {},
		digUp = {},
		digDown = {} -- To make it detect changes before/after digging
	}

	-- Set each one as a method on ourselves which does the customized movement
	for k,v in pairs(directions) do
		v.Name = k
		v.BaseMethod = turtle[k]
		self[k] = function() return self:PerformMovement(v) end
	end
end

---@private
function Client:Initialize()
	self.CurrentVersion = Extensions.ReadVersionFile() or ""
	self:SetupMovementDirections()

	self:RefuelFromInventoryIfNeeded()

	local x,y,z = gps.locate()
	if x and y and z then
		self.Position = vec3(x,y,z)
		print("Determined GPS position: ", self.Position)
		self:DetectGpsOrientation()
	else
		error("Couldn't get GPS position, which is now required")
	end
end



-- Exposed public methods below, to be used over rednet
-- Technically, the server can call any of our methods, but the previous ones should be hidden from intellisense with annotations cuz it shouldn't use them

-- Override method for wrappable, which will include this in every response we send
function Client:GetStateInfo()
    return { Position = self.Position, Orientation = self.Orientation, CurrentVersion = self.CurrentVersion } ---@type TurtleState
end

function Client:GetPositionData()
	return { Position = self.Position, Orientation = self.Orientation } ---@type PositionData
end

-- Public interface methods
function Client:DetectGpsOrientation()
	for i=1, 4 do
		-- Try to move forward, if it fails, turn right
		if turtle.forward() then
			local x,y,z = gps.locate()
			if x and y and z then
				local prevPosition = self.Position
				self.Position = vec3(x,y,z)
				if prevPosition ~= self.Position then
					local diff = self.Position - prevPosition
					if diff.y == 0 then
						self.Orientation = diff
						print("Detected GPS Orientation: ", self.Orientation)
						return
					end
				end
			end
		else
			turtle.turnRight()
		end
	end
	-- If none of that worked, try to move up and repeat (or down if up isn't available)
	if not turtle.up() and not turtle.down() then
		error("Couldn't get orientation because we're stuck")
	end
	self:DetectGpsOrientation()
end

---@param newOrientation vec3
function Client:OrientTo(newOrientation)
	if self.Orientation == newOrientation then return end
	local turnAmount = self.Orientation:GetNumberOfTurnsTo(newOrientation)

	local turnMethod = self.turnRight
	if turnAmount < 0 then turnMethod = self.turnLeft end

	local absNumRotations = math.abs(turnAmount)
	while absNumRotations > 0 do
		turnMethod()
		absNumRotations = absNumRotations - 1
	end
end

---@param position vec3
function Client:TurnToFace(position)
	local direction = (position - self.Position):normalize()
	self:OrientTo(direction)
end

---@param position vec3
---@return boolean MoveSuccessful
function Client:MoveToward(position)
	-- We'll attempt to orient just in case, but in the case of following path, we should already be oriented
	self:TurnToFace(position)

	if self.Position == position or (self.Position.x == position.x and self.Position.y == position.y and self.Position.z == position.z) then
		return true
	end

	-- If the Y component >= 1, go up or down
	-- TODO: Evalute how we determine this and when we should go up/down
	local yComponent = (position - self.Position):dot(Orientations.Up)
	local success = false
	if yComponent >= 0.5 then
		success = self.up()
	elseif yComponent <= -0.5 then
		success = self.down()
	else
		success = self.forward()
	end
    
	return success
end

-- Will return Success = false if it failed because something was in the way, probably requiring re-pathing
---@param moveList MoveListData[]
---@return MoveListResult DetectedData
function Client:FollowPath(moveList)
	local result = { Success = true, BlockData = {} } ---@type MoveListResult

	for _,v in ipairs(moveList) do
		-- 1. Orient; the orientation of a move is the orientation required to reach it from the previous position
		self:OrientTo(v.Orientation)
		-- 2. Move toward
		if not self:MoveToward(v.Position) then
			result.Success = false
			break
		end
	end

	result.BlockData = self.BlockData
	self.BlockData = {}
	return result
end

function Client:SelectEmptySlot()
    -- We have 16 slots, ignore the fuel slot
    for i=1, 16 do
        if i ~= self.FuelSlot and self.getItemCount(i) == 0 then
            self.select(i)
            return true
        end
    end
    return false
end

function Client:MethodFor(methodName, orientation, param)
    -- We can sorta cheese this, in that if you give me 'suck', I can append Up or Down and return the method on the turtle
    if orientation == Orientations.Up then methodName = methodName .. "Up" end
    if orientation == Orientations.Down then methodName = methodName .. "Down" end
    return self[methodName](param)
end

---@param orientation vec3
---@return boolean SuckedAny
function Client:SuckFor(orientation)
    return self:MethodFor("suck", orientation)
end

---@param orientation vec3
---@return boolean DroppedAny
function Client:DropFor(orientation, amount)
    return self:MethodFor("drop", orientation, amount)
end

---@param orientation vec3
---@return boolean DigSuccess
function Client:DigFor(orientation)
    return self:MethodFor("dig", orientation)
end

---@param orientation vec3
---@return boolean suckedAny
function Client:SuckAll(orientation)
    local suckedAny = false
    while self:SelectEmptySlot() and self:SuckFor(orientation) do
        suckedAny = true
    end

    return suckedAny
end

function Client:WrapChestIn(orientation)
    local name = "front"
    if orientation == Orientations.Up then name = "top"
    elseif orientation == Orientations.Down then name = "bottom" end
    return peripheral.wrap(name)
end

function Client:CountItems(orientation, filter)
    local count = 0
    local chest = self:WrapChestIn(orientation)
    if chest then
        local items = chest.list()
        for k,v in pairs(items) do
            if v.name and v.count and v.count > 0 and (not filter or v.name:containsWildcard(filter)) then
                count = count + v.count
            end
        end
    end
    return count
end

function Client:DropAll(orientation, filter, desiredQuantity)
    for i=1, 16 do
        local detail = self.getItemDetail(i)
        if detail and (not filter or (detail.name and filter and detail.name:containsWildcard(filter))) then
            -- Check if it has enough or if we need to add more
            local numToTransfer = detail.count
            if desiredQuantity then
                -- Drop will error if it's bigger than count or stack size, so account for that here
                numToTransfer = math.min(detail.count, math.max(desiredQuantity - self:CountItems(orientation, filter), 0))
            end
            if numToTransfer > 0 then
                self.select(i)
                self:DropFor(orientation, numToTransfer)
            end
        end
    end
end

-- Just from inventory for now
function Client:RefuelFromInventory()

    local limit = self.getFuelLimit()/2
    -- Try to refuel from inventory first... for cases where we're starting with 0 fuel and not at a chest
    if self.getItemCount(self.FuelSlot) > 0 then
        self.select(self.FuelSlot)
        self.refuel() -- Don't drop it yet if it's bad fuel, we'll do that once we're at the chest so it's not everywhere
        if self.getFuelLevel() >= limit then return end
    end
    -- Even if our fuel slot was empty, if we're at 0 we can still try all other slots.  If not, use the chest
    --   so we can try to guarantee it doesn't use fuel that we might not want turtles to use
    if self.getFuelLevel() == 0 then
        print("Completely out of fuel, trying from inventory")
        for i=1, 16 do
            if self.getItemCount(i) > 0 then
                self.select(i)
                self.refuel()
                if self.getFuelLevel() >= limit then return end
            end
        end
    end
end

function Client:RefuelFromInventoryIfNeeded()
    if self.getFuelLevel() <= self.getFuelLimit()/2 then
        self:RefuelFromInventory() -- TODO: Refuel in other ways...
    end
end

function Client:UpdateLuaFiles()
	os.reboot() -- A reboot should make it update, IDK how else to ensure we close before the startup method runs the new one
end


---@private
function Client:Run()
	parallel.waitForAny(function() self:HandleAllRednetMessagesBlocking() end) -- Can add parallel if I need to add more things later, for now this will just loop forever
end

Client:Initialize()
Client:Run()
