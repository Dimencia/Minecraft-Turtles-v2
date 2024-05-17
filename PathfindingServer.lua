local Extensions = require("Extensions")
local logger = require("AdvancedLogging")
local vec3 = require("vec3")
local pathfindingLogic = require("PathfindingLogic")
local wrapperModule = require("RednetWrappable")

local currentVersion = Extensions.ReadVersionFile()

-- A wrapper class to represent a wrapped turtle
---@class TurtleWrapper : PathfindingClient
---@field Position vec3
---@field Orientation vec3
---@field Id number
---@field JobThread thread|nil
---@field CurrentVersion string
local turtleWrapper = wrapperModule.ServerBuilder.new({ HostedProtocolName = Extensions.TurtleClientProtocol }) -- Ignore the warning, because it 'spoofs' as NetworkMethods

function turtleWrapper:ResponseCallback(message)
    if message.State then
        local state = message.State ---@type TurtleState
        if state.CurrentVersion then self.CurrentVersion = state.CurrentVersion end
        if state.Position then self.Position = state.Position end
        if state.Orientation then self.Orientation = state.Orientation end
    end
end

function turtleWrapper:new(id)
    local object = {Id = id}
    local result = setmetatable(object, {__index = turtleWrapper})
    -- Upon initializing a wrapper, force the wrapped turtle to update files from github and restart
    result:UpdateLuaFiles()
    -- Then send a message to get state info; if this message isn't acked, it'll retry til it does, so it's OK that they're shutdown right now
    -- TODO: Consider how we can do that cleaner; ideally we don't return from the client til we're updated and reinitialized in the new logic
    result:GetStateInfo() -- Send rednet message to get state info, which will initialize via the response callback
    return result
end


logger:AddLogger(print, LogLevels.Debug)
logger:AddFileLogger("LogFile", LogLevels.Warning)

local turtleWrappers = {} ---@type table<integer, TurtleWrapper>
local blockData = {} ---@type table<string, BlockData>


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

local function getOrCreateWrapper(id)
    if not turtleWrappers[id] then
        local wrapper = turtleWrapper:new(id)
        if wrapper.CurrentVersion ~= currentVersion then
            -- Make it update and don't add it; we'll add it once it's done and comes back
            wrapper:UpdateLuaFiles()
        else
            turtleWrapper[id] = wrapper
        end
    end
    return turtleWrappers[id]
end

local function moveTurtleTo(wrapper, targetPositions)
    if not targetPositions then return nil end
	if not targetPositions[1] then return nil end
	if type(targetPositions[1]) ~= "table" then -- Allow single entry instead of a table
		targetPositions = {targetPositions}
	end

	local path = pathfindingLogic.GetPath(wrapper.Position, wrapper.Orientation, targetPositions, blockData)
	if not path then
		print("Failed to pathfind to ", targetPositions)
		return nil 
	end

	local followResult = wrapper:FollowPath(path)

	-- If successful, extract the orientation from the last path entry to return it
	--   so you can tell if it's Up or Down for whatever you want to do at it
    followResult.ChestOrientation = path[#path].Orientation

    if followResult and followResult.BlockData then
        for k,v in pairs(followResult.BlockData) do
            blockData[k] = v
        end

        if not followResult.Success then
            print("Repathfinding...")
            return moveTurtleTo(wrapper, targetPositions)
        end
    end

	return followResult
end

local function doTurtleTransport(turtleId)
    local wrapper = getOrCreateWrapper(turtleId)

    -- Get its current position data before we start, at this point it may not really be set
    local posData = wrapper:GetPositionData()
    wrapper.Position = posData.Position
    wrapper.Orientation = posData.Orientation

    while true do
        local result = moveTurtleTo(wrapper, sourceChestPositions)
        if result then
            -- Load from chest
            local suckedAny = wrapper:SuckAll(result.ChestOrientation)
            wrapper:RefuelFromInventoryIfNeeded()
            --if suckedAny then
                -- Iterate item chests and see if we have any items for each one in order
                -- Overflow will hit the last wildcard naturally, assuming there is one
                for _,chest in ipairs(itemChests) do
                    for i=1, 16 do
                        local detail = wrapper:GetItemDetail(i)
                        if detail and detail.name and (not chest.Filter or detail.name:containsWildcard(chest.Filter)) then
                            -- We have an item in our list, go to that chest and drop off
                            result = moveTurtleTo(wrapper, chest.ChestPositions)
                            if result then
                                wrapper:DropAll(result.ChestOrientation, chest.Filter, chest.DesiredQuantity)
                            end
                        end
                    end
                end
            --end
        end
    end 
end

local function handleJobError(err)
    logger:LogError(err)
end

local function doJob(jobMethod, ...)
    xpcall(jobMethod, handleJobError, ...)
end

local function ensureTurtleWorkStarted(id)
    local wrapper = getOrCreateWrapper(id)
    if not wrapper.JobThread or coroutine.status(wrapper.JobThread) == "dead" then
        -- Fire off the coroutine to do whatever it needs to do
        local co = coroutine.create(doJob)
        wrapper.JobThread = co
        -- This will end up yielding when we hit the rednet.receive of the wrapper, which is good
        coroutine.resume(co, doTurtleTransport, id)
    end
end

-- Periodically looks up turtles to add/remove their wrappers
local function discoverTurtlesBlocking()
    while true do
        local turtleIds = table.pack(rednet.lookup(Extensions.TurtleClientProtocol))

        if turtleIds and #turtleIds > 0 then
            local toRemove = {}
            -- Iterate our existing wrappers.  Any that don't exist in these Ids need to be removed
            for id,wrapper in pairs(turtleWrappers) do
                if not table.icontains(turtleIds, id) then
                    toRemove[#toRemove+1] = id
                    -- We can only close suspended coroutines, not dead ones (and they wouldn't be running, when we get to here)
                    if wrapper.JobThread and coroutine.status(wrapper.JobThread) == "suspended" then
                        coroutine.close(wrapper.JobThread)
                        wrapper.JobThread = nil
                    end
                end
            end
            for _, id in ipairs(toRemove) do
                turtleWrappers[id] = nil
            end

            -- Then add/create/start work for all Ids that do exist, if not already added/created/started
            for _,v in pairs(turtleIds) do
                ensureTurtleWorkStarted(v)
            end
        end

        sleep(5) -- Wait 5 seconds before we continue
    end
end


local function run()
    if not Extensions.TryOpenModem() then error("Couldn't open modem") end

    while true do
        parallel.waitForAny(discoverTurtlesBlocking)
    end
end



run()
