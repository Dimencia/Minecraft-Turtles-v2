
-- This should be a wrapper over rednet to a Turtle
-- Logic has the interface, which is a bit awkward... but we can't multi inherit in annotations
-- And if we just extend logic instead, it'll work out the way I want it


-- Otherwise, initialization involves iterating every method in PathfindingTurtleInterface and making some generic rednet logic
--   which will send a request, the client will get it and call a method, and return the results over rednet

local Extensions = require("Extensions")
local networkMethods = require("PathfindingNetworkMethods")
local turtleLogic = require("PathfindingTurtleLogic")
local json = require("json")
local vec3 = require("vec3")
local BlockData, PositionData, MoveListData, MoveListResult, DirectionDefinition, TurtleRednetMessage = table.unpack(require("PathfindingTurtleBase"))

---@class PathfindingRednetTurtle : PathfindingTurtleLogic
---@field LastPathfindPositions vec3[]
---@field Id integer
---@field CoroutineMap table<string, thread>
local PathfindingRednetTurtle = turtleLogic:new() 
PathfindingRednetTurtle.CoroutineMap = {}
PathfindingRednetTurtle.LastPathfindPositions = {}

-- Thanks, internet.  https://gist.github.com/jrus/3197011
local random = math.random -- I suspect this needs to stay out of scope of the method, that's fine
---@return string
local function CreateGuid()
    local template ='xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx'
    return string.gsub(template, '[xy]', function (c)
        local v = (c == 'x') and random(0, 0xf) or random(8, 0xb)
        return string.format('%x', v)
    end)
end


-- We're gonna need a map of GUID to coroutine
-- Also, note that we'll have many instances of turtles, each with their own set of these, so at least we don't have to worry about that


-- We'll use this in our coroutine
function PathfindingRednetTurtle:SendMessage(targetId, protocol, ...)
    -- We'll always pack the ..., and always unpack it on the other end

    -- We need an identifier so we know how to pair the response with this message
    local identifier = CreateGuid()
    -- We then need to wrap our message with it
    local message = TurtleRednetMessage:new { Identifier = identifier, Data = table.pack(...) }
    rednet.send(targetId, json.encode(message), protocol)

    local routine = coroutine.running() -- Get the current coroutine and suspend it
    -- Store it in our map

    -- TODO: Is it possible one's running while we hit this again?  Probably... Esp if a method may not respond
    -- But that should be OK, it may come in later... 

    self.CoroutineMap[identifier] = routine
    return coroutine.yield()
end


-- What I've found is that our coroutine resumes itself without a response; I think because it was the main thread
-- So we should make sure to always run these on a new separate coroutine

function PathfindingRednetTurtle:SetupRednetMethods()
    for k,v in pairs(networkMethods) do
        if type(v) == "function" then
            self[k] = function(...)
                if not Extensions.TryOpenModem() then error("Modem couldn't be opened") end

                return self:SendMessage(self.Id, k, ...) -- Function name is the protocol name
            end
        end
    end
end

---@return PathfindingRednetTurtle
---@param values PathfindingRednetTurtle
function PathfindingRednetTurtle:new(values)
    values = values or turtleLogic:new()
    local result = setmetatable(values, self)
    self.__index = self
    result:SetupRednetMethods()
    return result
end

return PathfindingRednetTurtle
