-- Provides methods to be able to print table entities, and print to file as well as console
-- You may want to replace the default 'print' method with the new one, up to you...

-- Let's also do some more robust logging stuff.  For example, log levels
-- And, we're going to do this as globals so we don't have to redefine log levels and etc for each place we use it

if not LogLevels then
	-- For ease of use when specifying things
	LogLevels = {
		Debug = 1,
		Info = 2,
		Warning = 3,
		Error = 4
	}
end

-- If this gets required but is already initialized, we don't want to overwrite it, so just return the existing
if Logger then return Logger end

local Extensions = require("Extensions")

Logger = { Loggers = {} }


-- Adds a method to be called when something is logged at/above the given loglevel
-- logMethod should accept a string, which will be the serialized values given to us
function Logger:AddLogger(logMethod, logLevel)
	self.Loggers[#self.Loggers+1] = { LogMethod = logMethod, LogLevel = logLevel }
end

local function logToFile(fileName, message)
	local logFile = fs.open(fileName, "a")
	logFile.writeLine(message)
	logFile.flush()
	logFile.close()
end

local function getFileLogMethod(fileName)
	return function(message) logToFile(fileName, message) end
end

function Logger:AddFileLogger(fileName, logLevel)
	fileName = fileName or "LogFile"
	self:AddLogger(getFileLogMethod(fileName), logLevel)
end

function Logger:Log(logLevel, ...)
	-- For each argument, serialize it and append it
	local message = ""
	for _,v in ipairs(table.pack(...)) do
		message = message .. textutils.serialize(v)
	end

	for _, logger in ipairs(self.Loggers) do
		if logger.LogLevel >= logLevel then
			logger.LogMethod(message)
		end
	end
end

function Logger:LogDebug(...)
	self:Log(LogLevels.Debug, ...)
end
function Logger:LogInfo(...)
	self:Log(LogLevels.Info, ...)
end
function Logger:LogWarning(...)
	self:Log(LogLevels.Warning, ...)
end
function Logger:LogError(...)
	self:Log(LogLevels.Error, ...)
end

local oldErrorMethod = error
local function errorHandler(message, level)
	Logger:LogError(message)
	oldErrorMethod(message, level)
end

-- Let's override the 'error' method so we kinda inherently always send them to logger, before also sending them to the usual handler
error = errorHandler


return Logger