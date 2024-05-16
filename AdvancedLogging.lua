-- Provides methods to be able to print table entities, and print to file as well as console
-- You may want to replace the default 'print' method with the new one
local json = require("json")
local logger = {}
logger.FileName = "Logfile"
logger.OriginalPrint = print

local function vectorToString(vec)
	return vec.x .. "," .. vec.y .. "," .. vec.z
end

logger.GetDisplayString = function(object)
	return json.encode(object)
end


logger.Print = function(...)
    
    local result = ""
	for k,v in pairs(table.pack(...)) do
		result = result .. logger.GetDisplayString(v) .. " "
	end
    logger.OriginalPrint(result)

    local logFile = fs.open(logger.FileName, "a")
	logFile.writeLine(result)
	logFile.flush()
	logFile.close()
end

return logger