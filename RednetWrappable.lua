-- Generalized Rednet Wrapper

-- Send Process:
--   1. Send message over rednet to the client/implementation
--   2. Wait for an acknowledgement method, with a timeout.  If it times out, retry until it doesn't
--   3. Wait for the actual response, which may contain error info
--   4. If the response is an error, trigger an error.  Otherwise, return the result

-- This module returns a wrappable class, and wrapper class, to be new'd as appropriate by extending classes

local Extensions = require("Extensions")
local json = require("json")
local expectModule = require "cc.expect"
local expect = expectModule.expect
local logger = require("AdvancedLogging")

-- Structure for a message sent to a wrappable
---@class WrappedRednetMessage
---@field Identifier string
---@field Arguments table
---@field MethodName string
---@field ShouldInjectSelf boolean|nil

-- Structure for a response from a wrappable method call
---@class WrappedRednetResponse
---@field Data table|nil The packed return value(s) from the method call, nil if an exception occurred
---@field Exception string|nil If an exception occurred, the message from the exception
---@field State table|nil Optional state data from the client, separate from return values, set via GetStateInfo implementation


-- Ensure very unique identifiers with a guid, plus also the Id, MethodName, and current unix timestamp
---@param targetId number
---@param methodName string
---@return string
local function getIdentifier(targetId, methodName)
    expect(1, targetId, "number")
    expect(2, methodName, "string")
    return Extensions.CreateGuid() .. "_" .. targetId .. "_" .. methodName .. "_" .. os.time(os.date("*t"))
end

---@param identifier string
---@return string
local function getAcknowledgementProtocol(identifier)
    expect(1, identifier, "string")
    return "Acknowledgement_" .. identifier
end

-- Gets an error handler method that will log the error, and send a response to the given sourceId and protocol containing it (as a WrappedRednetResponse)
---@param sourceId number
---@param protocol string
---@return fun(any)
local function getErrorHandlerMethod(sourceId, protocol)
    expect(1, sourceId, "number")
    expect(2, protocol, "string")
    return function(err)
        logger:LogError(err)
        local response = { Exception = tostring(err) } ---@type WrappedRednetResponse
        rednet.send(sourceId, response, protocol)
    end
end


-- So actually... wrappable doesn't need to be extended by a client implementation, not really
-- All it really does is handle messages on the entity given to it in new, which can just be the client
-- So then it's hardly even newing, but more registering...  

-- Wait tho.  The client already has a metatable, turtle...

-- If we pass it to a wrapclient, it'll set its metatable again

-- And if we pass the turtle to a wrap client, the self it uses won't reference our client... 

-- I think what we do is a client = turtle, then we set stuff on it and etc, and when all setup, we make a wrapClient from it, cuz it doesn't have a metatable at that point anyway


-- But, we do also want to make a class extending wrapClient to define GetStateInfo


-- Structure for a wrappable class, to be extended by classes that want to be able to get wrapped over rednet, since they'll need to specify a protocol name
---@class RednetWrapClient
---@field HostedProtocolName string The protocol that an implementor should host, or remote service should lookup
local RednetWrappable = { }

-- An overridable method that we call whenever we're sending a response message from a client, to populate state data in that response
---@return table|nil
function RednetWrappable:GetStateInfo()
end

-- Handles a message on a client implementation, acknowledging it, calling the method with exception handling, and returning a response over rednet
---@param message string
---@param sourceId number
---@param protocol string
function RednetWrappable:HandleMessage(sourceId, message, protocol)
    expect(1, sourceId, "number")
    expect(2, message, "string")
    logger:LogDebug("Handling wrapper client message.  Protocol: ", protocol, ", Message: ", message)

    local deserialized = json.decode(message) 
    -- If we can't deserialize the message, or it doesn't have an identifier, we can't even report errors, so we just give up and exception ourselves
    if not deserialized or not deserialized.MethodName or not deserialized.Identifier then 
        error("Couldn't deserialize request message: " .. message)
    end

    local errorHandler = getErrorHandlerMethod(sourceId, deserialized.Identifier)

    if not self[deserialized.MethodName] or type(self[deserialized.MethodName] ~= "function") then
        errorHandler("Requested method did not exist on client: " .. deserialized.MethodName)
        return
    end

    -- Send acknowledgement
    rednet.send(sourceId, "", getAcknowledgementProtocol(deserialized.Identifier))
    logger:LogDebug("Sent acknowledgement to " .. sourceId .. " for message ", message)

    local arguments = deserialized.Arguments
    if deserialized.ShouldInjectSelf then
        table.insert(arguments, 1, self)
    end

    local results = {xpcall(self[deserialized.MethodName], getErrorHandlerMethod(sourceId, protocol), table.unpack(arguments))}
    local success = table.remove(results, 1) -- Remove the xpcall success value from the result collection

    -- If not successful, the error handler already sent the response with the error in it
    if success then
        local state = self:GetStateInfo()
        rednet.send(sourceId, WrappedRednetResponse.new { Data = results, State = state }, protocol)
        logger:LogDebug("Sent result to " .. sourceId .. "; Original Message: ", message, ", Response: ", results)
    end
end

-- The method that should be used with parallel.waitForAny to constantly listen for and handle messages for our class
function RednetWrappable:HandleAllRednetMessagesBlocking()
    -- Set ourselves as hosting our protocol when we begin trying to process messages
    if not Extensions.TryOpenModem() then error("Couldn't open modem") end
    rednet.host(self.HostedProtocolName)
    while true do
		local senderId, message = rednet.receive(self.HostedProtocolName)
        self:HandleMessage(senderId, message, self.HostedProtocolName)
	end
end

-- Finds a device hosting the protocol for this class, and returns its Id.  Blocks until one is found, returns first one if multiple
---@param retryDelay number|nil
---@return integer
function RednetWrappable:FindHostId(retryDelay)
    if not retryDelay then retryDelay = 1 end
    local clients = table.pack(rednet.lookup(self.HostedProtocolName))
    if not clients or #clients == 0 then
        sleep(retryDelay)
        return self:FindHostId(retryDelay)
    end
    return clients[1]
end

-- Finds all devices hosting the protocol for this class, and returns their Ids.  Returns an empty collection if none are found
---@return integer[]
function RednetWrappable:FindAllIds()
    return table.pack(rednet.lookup(self.HostedProtocolName))
end

-- Chained inheritance gets weird, but I believe combining the metatables should solve all the problems

-- To be returned from the module
local clientBuilder = {}
---@return RednetWrapClient
function clientBuilder.new(object)
    object = object or {}
    return setmetatable(object, { __index = RednetWrappable })
end





-- And then another class representing a wrapper on a server, which will have some callbacks and most of this logic
-- Extend this with your own custom class and setup callbacks, customization, and inheritance 
-- (IE your implementation should have annotations saying it extends the wrappable that you want to wrap, but ofc, doesn't need to actually extend it)
---@class RednetWrapper
---@field Id integer
---@field AcknowledgementTimeoutSeconds integer
---@field HostedProtocolName string
---@field ResponseCallback fun(RednetWrapper, WrappedRednetResponse)|nil
local RednetWrapper = { AcknowledgementTimeoutSeconds = 3 }

---@param targetId number
---@param methodName string
---@param ... any
---@return any
function RednetWrapper:SendMessage(targetId, methodName, shouldInjectSelf, ...)
    expect(1, targetId, "number")
    expect(2, methodName, "string")

    local identifier = getIdentifier(targetId, methodName)

    local message = { Identifier = identifier, Arguments = table.pack(...), MethodName = methodName, ShouldInjectSelf = shouldInjectSelf } ---@type WrappedRednetMessage
    logger:LogDebug("Sending message to " .. targetId .. ": ", message)
    rednet.send(targetId, json.encode(message), self.HostedProtocolName)

    -- Wait for an acknowledgement response
    local senderId, ackMessageRaw = rednet.receive(getAcknowledgementProtocol(identifier), self.AcknowledgementTimeoutSeconds)
    if not senderId or not ackMessageRaw then
        -- Try to send it again
        logger:LogWarning("Acknowledgement timed out; retrying. ID: ", targetId, ", Message: ", message)
        return self:SendMessage(targetId, methodName, ...)
    end

    -- Wait for the second response, with the results from the method call, with the identifier as protocol
    local _, responseMessageRaw = rednet.receive(identifier)
    logger:LogDebug("Received response for wrapped message.  Message: ", message, ", Response: ", responseMessageRaw)
    -- We can guarantee that both aren't nil, I think

    local responseData = json.decode(responseMessageRaw)
    if not responseData then error("Failed to decode wrapped response method.  Message: " .. responseMessageRaw) end
    if responseData.Exception then error(responseData.Exception) end

    if self.ResponseCallback then
        self:ResponseCallback(responseData)
    end
    -- Note that if a nil is returned, we already packed it, so unpacking it should give it back to us I think...
    return table.unpack(responseData.Data)
end

-- the static Wrapper class's metatable should generically point at SendMessage endpoints that it implements and will take in the implementing instance
setmetatable(RednetWrapper, {
    __index = function(wrapperImplementation, methodName)
        return function(...)
            -- If it was called as :method, remove the wrapper from the arguments and flag to re-inject self on the other side
            -- It's still up to the caller to notice and use the correct call type
            local firstArg = ...
            if firstArg == wrapperImplementation then
                return wrapperImplementation:SendMessage(wrapperImplementation.Id, methodName, true, select(2, ...))
            else
                return wrapperImplementation:SendMessage(wrapperImplementation.Id, methodName, false, ...)
            end
        end
    end
})

local serverBuilder = {}
-- And making a new wrapper will make a new object with a metatable to the static wrapper class
-- So there's no need to explicitly Wrap, it's already wrapped just by existing
---@return RednetWrapper
function serverBuilder.new(object)
    object = object or {}
    return setmetatable(object, { __index = RednetWrapper })
end


return {ClientBuilder = clientBuilder, ServerBuilder = serverBuilder}