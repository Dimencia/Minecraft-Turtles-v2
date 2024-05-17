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

-- Detect if the device is a turtle or a computer
local isTurtle = turtle and true or false
local deviceType = isTurtle and "Turtle" or "Computer"

-- Function to update all files listed in files.json
local function updateFiles()
    local response = http.get(files_json_url)
    if response then
        local config = textutils.unserializeJSON(response.readAll())
        if config then
            -- Update files based on device type
            for file, attributes in pairs(config) do
                if table.contains(attributes.ComputerTypes, deviceType) then
                    local url = repo_url .. file
                    download(url, file)
                end
            end
        end
        response.close()
    else
        print("Failed to fetch files list from " .. files_json_url)
    end
end

-- Function to update the startup script itself
local function updateStartup()
    download(repo_url .. "startup.lua", "startup.lua")
end

local versionFileName = "version.txt"

local function readVersionFile()
    if not fs.exists(versionFileName) then return nil end
    local file = fs.open(versionFileName, "r")
    local versionString = file.readAll()
    file.close()
    return versionString
end

local function shouldUpdate()
    local originalVersion = readVersionFile()
    download(repo_url .. versionFileName, versionFileName)
    local newVersion = readVersionFile()
    return originalVersion ~= newVersion
end

-- Main update logic
local function update(isSecondRun)
    if not shouldUpdate() then return end
    if not isSecondRun then
        updateStartup()
        -- Run the updated startup script with an argument indicating it's the second run
        shell.run("startup.lua", "second_run")
        return
    end
    updateFiles()
end

-- Check if this is the second run
local isSecondRun = false
local args = {...}
if args[1] == "second_run" then
    isSecondRun = true
end

-- Perform update
update(isSecondRun)

-- If this is the second run, run the main file for the device type
if isSecondRun then
    local response = http.get(files_json_url)
    if response then
        local config = textutils.unserializeJSON(response.readAll())
        if config then
            for file, attributes in pairs(config) do
                if attributes.ComputerTypes and table.contains(attributes.ComputerTypes, deviceType) and attributes.IsMain then
                    shell.run(file)
                    break
                end
            end
        end
        response.close()
    end
end

-- Add a manual trigger to update from command
shell.setAlias("update", "lua update()")

