local vec3 = require("vec3")


---@class BlockData
---@field Position vec3
---@field Name string
---@field IsOccupied boolean
---@field ComputerId integer|nil
local BlockData = {}

---@return BlockData
---@param values BlockData
function BlockData:new(values)
    self.__index = self
    return setmetatable(values or {}, self)
end


---@class PositionData
---@field Position vec3
---@field Orientation vec3
local PositionData = {}

---@return PositionData
---@param values PositionData
function PositionData:new(values)
    self.__index = self
    return setmetatable(values or {}, self)
end

-- We want both position and orientation, so we don't have to worry about an unpathable end-target, 
-- It will just end with a move that is to the same position and faces the target

-- Tempted to make it a literal list of string moves or method names, but nah, we'll leave it like this
-- So the logic for doing them can be abstracted to turtle to keep the server from having to go one instruction at a time
---@class MoveListData
---@field Position vec3
---@field Orientation vec3
---@field Parent MoveListData
local MoveListData = {}

---@return MoveListData
---@param values MoveListData
function MoveListData:new(values)
    self.__index = self
    return setmetatable(values or {}, self)
end


---@class MoveListResult
---@field Success boolean
---@field BlockData table<vec3, BlockData>
---@field Orientation vec3 Final orientation
---@field Position vec3 Final position
local MoveListResult = {}

---@return MoveListResult
---@param values MoveListResult
function MoveListResult:new(values)
    self.__index = self
    return setmetatable(values or {}, self)
end


---@class DirectionDefinition
---@field PositionChange fun():vec3|nil
---@field RotationChange integer|nil
---@field BaseMethod fun():boolean, string|nil
local DirectionDefinition = {}

---@param values DirectionDefinition
---@return DirectionDefinition
function DirectionDefinition:new(values)
	values = values or {}
	if not values.PositionChange then values.PositionChange = function() return nil end end
    self.__index = self
	return setmetatable(values, self)
end



---@class TurtleRednetMessage
---@field Identifier string
---@field Data table

local TurtleRednetMessage = {}
---@return TurtleRednetMessage
---@param values TurtleRednetMessage
function TurtleRednetMessage:new(values)
    self.__index = self
    return setmetatable(values or {}, self)
end



return {BlockData, PositionData, MoveListData, MoveListResult, DirectionDefinition, TurtleRednetMessage}
-- local BlockData, PositionData, MoveListData, MoveListResult, DirectionDefinition = table.unpack(require("PathfindingTurtleBase"))