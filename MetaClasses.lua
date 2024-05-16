-- Class definitions that don't really go anywhere else... 
-- TODO: Find a place to put them

---@class BlockData
---@field Position vec3
---@field Name string
---@field IsOccupied boolean
---@field ComputerId integer|nil


---@class PositionData
---@field Position vec3
---@field Orientation vec3


---@class MoveListData
---@field Position vec3
---@field Orientation vec3
---@field Parent MoveListData|nil


---@class MoveListResult
---@field Success boolean
---@field BlockData table<string, BlockData>



---@class DirectionDefinition
---@field PositionChange fun():vec3|nil
---@field RotationChange integer|nil
---@field BaseMethod fun():boolean, string|nil
local DirectionDefinition = {}



---@class TurtleRednetMessage
---@field Identifier string
---@field Data table
