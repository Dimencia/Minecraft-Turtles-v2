-- This is where we'll define client implementations of methods that the server should be able to rednet
local Orientations = require("Orientations")
local vec3 = require("vec3")
local BlockData, PositionData, MoveListData, MoveListResult, DirectionDefinition, Orientation, TurtleRednetMessage = table.unpack(require("PathfindingTurtleBase"))
local Extensions = require("Extensions")


---@class PathfindingTurtleNetworkMethods
---@field BlockData table<vec3, BlockData>
---@field Position vec3
---@field Orientation vec3
local networkMethodsClass = { BlockData = {} }

function networkMethodsClass:new(values)
    values = values or {}
    self.__index = self
    return setmetatable(values, self)
end

---@return PositionData
function networkMethodsClass:GetPositionData()
	return PositionData:new { Position = self.Position, Orientation = self.Orientation }
end

-- Public interface methods
function networkMethodsClass:DetectGpsOrientation()
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

function networkMethodsClass:GetPositionData()
    return PositionData:new {Position = self.Position, Orientation = self.Orientation}
end

---@param newOrientation vec3
function networkMethodsClass:OrientTo(newOrientation)
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
function networkMethodsClass:TurnToFace(position)
	local direction = (position - self.Position):normalize()
	self:OrientTo(direction)
end

---@param position vec3
---@return boolean MoveSuccessful
function networkMethodsClass:MoveToward(position)
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
function networkMethodsClass:FollowPath(moveList)
	local result = MoveListResult:new { Success = true, BlockData = {} }

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
    result.Orientation = self.Orientation
    result.Position = self.Position
	return result
end

function networkMethodsClass:SelectEmptySlot()
    -- We have 16 slots, ignore the fuel slot
    for i=1, 16 do
        if i ~= self.FuelSlot and self.getItemCount(i) == 0 then
            self.select(i)
            return true
        end
    end
    return false
end

function networkMethodsClass:MethodFor(methodName, orientation, param)
    -- We can sorta cheese this, in that if you give me 'suck', I can append Up or Down and return the method on the turtle
    if orientation == Orientations.Up then methodName = methodName .. "Up" end
    if orientation == Orientations.Down then methodName = methodName .. "Down" end
    return self[methodName](param)
end

---@param orientation vec3
---@return boolean SuckedAny
function networkMethodsClass:SuckFor(orientation)
    return self:MethodFor("suck", orientation)
end

---@param orientation vec3
---@return boolean DroppedAny
function networkMethodsClass:DropFor(orientation, amount)
    return self:MethodFor("drop", orientation, amount)
end

---@param orientation vec3
---@return boolean DigSuccess
function networkMethodsClass:DigFor(orientation)
    return self:MethodFor("dig", orientation)
end

---@param orientation vec3
---@return boolean suckedAny
function networkMethodsClass:SuckAll(orientation)
    local suckedAny = false
    while self:SelectEmptySlot() and self:SuckFor(orientation) do
        suckedAny = true
    end

    return suckedAny
end

function networkMethodsClass:WrapChestIn(orientation)
    local name = "front"
    if orientation == Orientations.Up then name = "top"
    elseif orientation == Orientations.Down then name = "bottom" end
    return peripheral.wrap(name)
end

function networkMethodsClass:CountItems(orientation, filter)
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

function networkMethodsClass:DropAll(orientation, filter, desiredQuantity)
    for i=1, 16 do
        local detail = turtle.getItemDetail(i)
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
function networkMethodsClass:RefuelFromInventory()

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


function networkMethodsClass:RefuelFromInventoryIfNeeded()
    if self.getFuelLevel() <= self.getFuelLimit()/2 then
        self:RefuelFromInventory() -- TODO: Refuel in other ways...
    end
end

function networkMethodsClass:getItemDetail(index)
    return turtle.getItemDetail(index)
end

return networkMethodsClass