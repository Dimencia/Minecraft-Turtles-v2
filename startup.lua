-- Path to the GitHub repo (replace with actual repo URL)
local repo_url = "https://raw.githubusercontent.com/Dimencia/Minecraft-Turtles-v2/main/"

-- File that lists other files to update
local files_json_url = repo_url .. "files.json"

local function stringSplit (self, sep)
	if sep == nil then
			sep = "%s"
	end
	local t={}
	for str in string.gmatch(self, "([^"..sep.."]+)") do
			table.insert(t, str)
	end
	return t
end

-- Utility function to check if a table contains a value
function table.contains(tbl, val)
    for _, v in ipairs(tbl) do
        if v == val then
            return true
        end
    end
    return false
end

local function trimLuaExtension(filename)
    return filename:gsub("%.lua$", "")
end

-- Our 'main' files execute by just requiring them, rather than returning like a module
local function runMain(fileName, retry)
    local trimmed = trimLuaExtension(fileName)
    while true do
        xpcall(function() require(trimmed) end, function(err) print("Error in main file: " .. err) end)
        if not retry then break end
    end
end

-- Function to download a file from a URL
local function download(url, path)
    local response = http.get(url)
    if response then
        local content = response.readAll()
        local file = fs.open(path, "w")
        file.write(content)
        file.close()
        response.close()
    else
        print("Failed to download " .. url)
    end
end


local function readFile(fileName)
    if not fs.exists(fileName) then return nil end
    local file = fs.open(fileName, "r")
    local content = file.readAll()
    file.close()
    return content
end

-- Detect if the device is a turtle or a computer
local isTurtle = turtle and true or false
local deviceType = isTurtle and "Turtle" or "Computer"

local function getMainFile()
    local config = textutils.unserializeJSON(readFile("files.json"))
    if config then
        -- Update files based on device type
        for file, attributes in pairs(config) do
            if table.contains(attributes.ComputerTypes, deviceType) then
                if attributes.IsMain then
                    return file
                end
            end
        end
    end
end

-- Function to update all files listed in files.json
local function updateFiles()
    download(files_json_url, "files.json")
    local config = textutils.unserializeJSON(readFile("files.json"))
    if config then
        -- Update files based on device type
        for file, attributes in pairs(config) do
            if table.contains(attributes.ComputerTypes, deviceType) then
                local url = repo_url .. file
                download(url, file)
            end
        end
    end
end

-- Function to update the startup script itself
local function updateStartup()
    download(repo_url .. "startup.lua", "startup.lua")
end

local versionFileName = "version.txt"

local function shouldUpdate()
    local originalVersion = readFile(versionFileName)
    download(repo_url .. versionFileName, versionFileName)
    local newVersion = readFile(versionFileName)
    return originalVersion ~= newVersion
end

local function findRunMain()
    runMain(getMainFile(), true) -- Retry/loop back into it repeatedly if it crashes
end

-- Main update logic
local function update()
    if not Startup_Method_Is_Second_Run then
        if not shouldUpdate() then findRunMain() return end
        updateStartup()
        Startup_Method_Is_Second_Run = true
        -- Run the updated startup script again... with our global set, it should now do the second pass
        runMain("startup")
        return
    end
    updateFiles()
    Startup_Method_Is_Second_Run = false
    findRunMain()
end


-- Perform update
update()