local vec3 = require("vec3")

---@class Orientations
local Orientations = {
	North = vec3(0,0,-1),
	East = vec3(1,0,0),
	South = vec3(0,0,1),
	West = vec3(-1,0,0),
	Up = vec3(0,1,0),
	Down = vec3(0,-1,0)
} -- Possible orientations, for use with methods

return Orientations