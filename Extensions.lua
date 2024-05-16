---@class Extensions
local Extensions = {}


Extensions.TurtleHostedProtocol = "RednetTurtleClient"

---@param methodName string
---@param orientation vec3
---@return string
function Extensions.GetMethodNameFor(methodName, orientation)
    -- We can sorta cheese this, in that if you give me 'suck', I can append Up or Down and return the method on the turtle
    if orientation == Orientations.Up then methodName = methodName .. "Up" end
    if orientation == Orientations.Down then methodName = methodName .. "Down" end
    return methodName
end

---@return boolean
function table:hasAnyElements()
	for k,v in pairs(self) do
		return true
	end
	return false
end

---@param input number
---@return integer
function Extensions.round(input)
	return math.floor(input+0.5)
end


---@return boolean
function Extensions.TryOpenModem()
	local modems = {peripheral.find("modem")}
	local success = false
	for k,v in pairs(modems) do
		success = true
		if not rednet.isOpen(peripheral.getName(v)) then
			rednet.open(peripheral.getName(v))
		end
	end
	return success
end

---@param start string
---@return boolean
function string:starts_with(start)
    return self:sub(1, #start) == start
 end
 
---@param ending string
---@return boolean
function string:ends_with(ending)
    return ending == "" or self:sub(-#ending) == ending
end

---@param wildcard string
---@return boolean
function string:containsWildcard(wildcard)
    local result = wildcard == "*" or (self == wildcard or (wildcard:starts_with("*") and self:ends_with(wildcard:sub(2, #wildcard))))
    return result
end

---@param element any
---@return boolean
function table:contains(element)
	for _, value in pairs(self) do
		if value == element then
		return true
		end
	end
	return false
end

---@param element any
---@return boolean
function table:icontains(element)
	for _, value in ipairs(self) do
		if value == element then
		return true
		end
	end
	return false
end

return Extensions