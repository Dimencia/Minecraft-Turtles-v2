local Extensions = require("Extensions")
local PathfindingRednetTurtle = require("PathfindingRednetTurtle")
local json = require("json")
local logging = require("AdvancedLogging")
local vec3 = require("vec3")
print = logging.Print

-- Now this, we won't make multiple instances of; just one, to coordinate them all
---@class PathfindingTurtleServer
---@field TurtleWrappers table<integer, PathfindingRednetTurtle>
---@field BlockData table<string, BlockData>
local pathfindingTurtleServer = { TurtleWrappers = {}, BlockData = {} }

-- Anytime we make a new turtle, we add the wrapper to this collection


-- We'll use this with parallel so it's always going
function pathfindingTurtleServer.HandleMessagesBlocking()
    while true do
        local senderId, message, protocol = rednet.receive()
        local wrapper = pathfindingTurtleServer.TurtleWrappers[senderId]
        if wrapper and message then
            -- Resume the waiting coroutine with the received message
            local deserialized
            if type(message) == "string" then deserialized = json.decode(message)
            else deserialized = message end
            if deserialized and deserialized.Identifier then
                local toResume = wrapper.CoroutineMap[deserialized.Identifier]
                if toResume then
                    -- We pack any results before sending them over rednet, unpack to return them
                    coroutine.resume(toResume, table.unpack(deserialized.Data))
                    wrapper.CoroutineMap[deserialized.Identifier] = nil
                end
            end
        else
            -- We got a message from a turtle that we aren't aware of... 
            -- Or it's not a turtle.  

            -- Let's do nothing for now, to avoid hardcoding that everything should be a turtle
        end
    end
end

local sourceChestPositions = {
    vec3(-40, 76, 17),
    vec3(-39, 76, 17),
}





-- Each chest position can allow multiple names for the same quantity, or multiple different ones... 
local itemChests = {
    {
        -- Fuel chest for logs
        ChestPositions = {
            vec3(-39, 75, 13),
            vec3(-40, 75, 13)
        },
        Filter = "*log",
        DesiredQuantity = nil -- Anything more than DesiredQuantity in the destination will overflow
    },
    {
        -- Stick chest for testing
        ChestPositions = {
            vec3(-48, 77, 16),
            vec3(-49, 77, 16)
        },
        Filter = "*stick",
        DesiredQuantity = 256
    },
    {
        -- Another random chest for overflow, which in my case will feed back to source
        ChestPositions = {
            vec3(-46, 76, 17),
            vec3(-47, 76, 17) 
        },
        Filter = "*"
        
    }
}

local refuelChestPositions = {
    vec3(-39, 75, 13),
    vec3(-40, 75, 13)
}

-- Self is a wrapper here, not really self
function pathfindingTurtleServer.MoveTurtleTo(self, targetPositions)
    if not targetPositions then return nil end
	if not targetPositions[1] then return nil end
	if type(targetPositions[1]) ~= "table" then -- Allow single entry instead of a table
		targetPositions = {targetPositions}
	end

	local path = self:GetPath(targetPositions, pathfindingTurtleServer.BlockData)
	if not path then
		print("Failed to pathfind to ", targetPositions)
		return nil 
	end

	local followResult = self.FollowPath(path)

	-- If successful, extract the orientation from the last path entry to return it
	--   so you can tell if it's Up or Down for whatever you want to do at it
	local lastPath = path[#path]
    followResult.ChestOrientation = lastPath.Orientation
    self.Position = followResult.Position
    self.Orientation = followResult.Orientation

    if followResult and followResult.BlockData then
        for k,v in pairs(followResult.BlockData) do
            pathfindingTurtleServer.BlockData[k] = v
        end

        if not followResult.Success then
            print("Repathfinding...")
            return pathfindingTurtleServer.MoveTurtleTo(self, targetPositions)
        end
    end

	return followResult
end

function pathfindingTurtleServer.PathTurtle(turtleId, positions)
    local wrapper = pathfindingTurtleServer.TurtleWrappers[turtleId]

    -- Get its position data first
    local posData = wrapper.GetPositionData()
    wrapper.Position = posData.Position
    wrapper.Orientation = posData.Orientation

    while true do
        local result = pathfindingTurtleServer.MoveTurtleTo(wrapper, positions)
        if result then
            -- Load from chest
            local suckedAny = wrapper.SuckAll(result.ChestOrientation)
            wrapper.RefuelFromInventoryIfNeeded()
            --if suckedAny then
                -- Iterate item chests and see if we have any items for each one in order
                -- Overflow will hit the last wildcard naturally, assuming there is one
                for _,chest in ipairs(itemChests) do
                    for i=1, 16 do
                        local detail = wrapper.getItemDetail(i)
                        if detail and detail.name and (not chest.Filter or detail.name:containsWildcard(chest.Filter)) then
                            -- We have an item in our list, go to that chest and drop off
                            result = pathfindingTurtleServer.MoveTurtleTo(wrapper, chest.ChestPositions)
                            if result then
                                wrapper.DropAll(result.ChestOrientation, chest.Filter, chest.DesiredQuantity)
                            end
                        end
                    end
                end
            --end
        end
    end 
end


function pathfindingTurtleServer.DoTransportJob(turtleId)
    xpcall(function()
    pathfindingTurtleServer.PathTurtle(turtleId, sourceChestPositions)
    end, function(x) print("Error in coroutine: ", x) end)
end



local coroutineMap = {}

function pathfindingTurtleServer.DiscoverTurtlesBlocking()
    while true do
        local turtleIds = table.pack(rednet.lookup(Extensions.TurtleHostedProtocol))

        if turtleIds and #turtleIds > 0 then
            local newWrappers = {}
            -- First, anything that's not in this list should be removed
            for k,v in pairs(pathfindingTurtleServer.TurtleWrappers) do
                if table.contains(turtleIds, k) then
                    newWrappers[k] = v -- Move to new list, we don't want to try to remove while iterating
                end
            end
            pathfindingTurtleServer.TurtleWrappers = newWrappers

            for k,v in pairs(turtleIds) do
                if not pathfindingTurtleServer.TurtleWrappers[v] then
                    pathfindingTurtleServer.TurtleWrappers[v] = PathfindingRednetTurtle:new { Id = v }
                end

                -- Temporary debug thing, 
                
                    -- Check if we have a coroutine already running
                    if not coroutineMap[v] or coroutine.status(coroutineMap[v]) == "dead" then
                        -- Fire off the coroutine to do whatever it needs to do
                        local co = coroutine.create(pathfindingTurtleServer.DoTransportJob)
                        coroutineMap[v] = co
                        coroutine.resume(co, v)
                    end
            end
            --term.clear()
            -- That's it for now.  In other logic, I can iterate these to give them commands
        end

        os.sleep(5) -- Wait 5 seconds before we continue
    end
end

-- Sorta just a placeholder, cuz I know I'm gonna want more things in parallel with the message handler, not sure what yet though
function pathfindingTurtleServer.ExtraLogic()
    
end

function pathfindingTurtleServer.Run()
    if not Extensions.TryOpenModem() then error("Couldn't open modem") end
    parallel.waitForAny(pathfindingTurtleServer.HandleMessagesBlocking, pathfindingTurtleServer.DiscoverTurtlesBlocking)
end



pathfindingTurtleServer.Run()
