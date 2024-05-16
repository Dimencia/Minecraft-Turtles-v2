-- A simple pathfinding turtle client, capable of following a list of moves from a pathfinding server and returning block data it detected

local BlockData, PositionData, MoveListData, MoveListResult, DirectionDefinition, TurtleRednetMessage = table.unpack(require("PathfindingTurtleBase"))
local networkMethods = require("PathfindingNetworkMethods")
local Extensions = require("Extensions")
local Orientations = require("Orientations")
-- TODO: Store and load these from some sub folder?  So they're not in the way making a mess of the files on the turtle
local vec3 = require("vec3")
local json = require("json")
local log = require("AdvancedLogging")
print = log.Print



-- Client implementations will perform actions and return data and whatnot
-- Rednet implementations will be made iteratively to query the client over rednet and get the values back

---@class PathfindingTurtleClient : PathfindingTurtleNetworkMethods
local Client = networkMethods:new { Id = os.getComputerID(), FuelSlot = 16 }

-- I think because networkMethods is mostly done via metatable, if I then set turtle, I'll overwrite it
-- So I need to make my own index with blackjack and hookers, cuz I don't want the network methods extending turtle
setmetatable(Client, {__index = function(t,k) if networkMethods[k] then return networkMethods[k] elseif turtle[k] then return turtle[k] end end})



-- Private client methods

-- When a turtle is in front, above, or below us, we can wrap it and get its ID
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

function Client:DetectBlocks()
	-- Detects all blocks and stores the data
	self:SetBlockData(self.Orientation)
	self:SetBlockData(Orientations.Up)
	self:SetBlockData(Orientations.Down)
end

-- A little weird, but centralizes the logic for moving in a sorta generic way
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

function Client:SetupMovementDirections()

	local directions = {
		forward = DirectionDefinition:new { PositionChange = function() return self.Orientation end },
		back = DirectionDefinition:new { PositionChange = function() return -self.Orientation end },
		up = DirectionDefinition:new { PositionChange = function() return Orientations.Up end },
		down = DirectionDefinition:new { PositionChange = function() return Orientations.Down end },
		turnLeft = DirectionDefinition:new { RotationChange = -1 },
		turnRight = DirectionDefinition:new { RotationChange = 1 },
		dig = DirectionDefinition:new {},
		digUp = DirectionDefinition:new {},
		digDown = DirectionDefinition:new {} -- To make it detect changes before/after digging
	}

	-- Set each one as a method on ourselves which does the customized movement
	for k,v in pairs(directions) do
		v.Name = k
		v.BaseMethod = turtle[k]
		self[k] = function() return self:PerformMovement(v) end
	end
end

function Client:Initialize()
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

	if not Extensions.TryOpenModem() then error("Couldn't open modem") end
	rednet.host(Extensions.TurtleHostedProtocol, os.getComputerID() .. "")
end

function Client:HandleMessagesBlocking()
	while true do
		local senderId, message, protocol = rednet.receive()
		if self[protocol] and type(self[protocol]) == "function" then
			local deserialized = json.decode(message)
			-- All our methods should take self as the first param
			local result = table.pack(self[protocol](self, table.unpack(deserialized.Data)))
			-- And, send it back on the same protocol and identifier
			-- Note that we always pack on the other end, so we always unpack here
			-- And we'll want to wrap any results in a packed table too, in case there are multiple
			local newMessage = TurtleRednetMessage:new { Identifier = deserialized.Identifier, Data = result }
			rednet.send(senderId, json.encode(newMessage), protocol)
		end
	end
end

function Client:Run()
	parallel.waitForAny(function() self:HandleMessagesBlocking() end) -- Can add parallel if I need to add more things later, for now this will just loop forever
end

Client:Initialize()
Client:Run()
