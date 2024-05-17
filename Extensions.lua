---@class Extensions
local Extensions = {}

Extensions.TurtleClientProtocol = "PathfindingTurtleClient"



local versionFileName = "version.txt"

function Extensions.ReadVersionFile()
    if not fs.exists(versionFileName) then return nil end
    local file = fs.open(versionFileName, "w")
    local versionString = file.readAll()
    file.close()
    return versionString
end


-- The 'standard' lua OOP pattern doesn't really chain inheritance well, esp if I want private vs public methods on the same class, and we need this to be able to do that
-- This will take an object, which has a metatable, and setup a new metatable for it which tries the new one first
function Extensions.AddMetatableIndexToExisting(existingObject, newIndex)
    local indexMethod = function(t, k)
            if newIndex[k] then return newIndex[k] end
			-- Then try the original object's __index
			-- Resolve this in the method, instead of before, so any changes to the metatable after this Add function is called are still respected
			local originalMetatable = getmetatable(existingObject)
			if type(originalMetatable.__index) == "function" then
                return originalMetatable.__index(t, k)
            elseif type(originalMetatable.__index) == "table" then
                return originalMetatable.__index[k]
			else
				return nil -- If it's neither table or function, it's not set
			end
        end
	return setmetatable(existingObject, {__index = indexMethod})
end

-- Thanks, internet.  https://gist.github.com/jrus/3197011
local random = math.random -- I suspect this needs to stay out of scope of the method

---@return string
function Extensions.CreateGuid()
    local template ='xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx'
    return string.gsub(template, '[xy]', function (c)
        local v = (c == 'x') and random(0, 0xf) or random(8, 0xb)
        return string.format('%x', v)
    end)
end

-- Concat the contents of the parameter list,
-- separated by the string delimiter (just like in perl)
-- example: strjoin(", ", {"Anna", "Bob", "Charlie", "Dolores"})
---@param self string[]
---@param delimiter string
---@return string
function table:Join(delimiter)
	local len = #self
	if len == 0 then
	   return "" 
	end
	local string = self[1]
	for i = 2, len do 
	   string = string .. delimiter .. self[i] 
	end
	return string
 end

 ---@param sep string
 ---@return string[]
 function string:Split (sep)
	if sep == nil then
			sep = "%s"
	end
	local t={}
	for str in string.gmatch(self, "([^"..sep.."]+)") do
			table.insert(t, str)
	end
	return t
end

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