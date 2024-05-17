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

-- Detect if the device is a turtle or a computer
local isTurtle = turtle and true or false
local deviceType = isTurtle and "Turtle" or "Computer"

-- Function to update all files listed in files.json
local function updateFiles()
    local response = http.get(files_json_url)
    local mainFile
    if response then
        local config = textutils.unserializeJSON(response.readAll())
        if config then
            -- Update files based on device type
            for file, attributes in pairs(config) do
                if table.contains(attributes.ComputerTypes, deviceType) then
                    local url = repo_url .. file
                    download(url, file)
                    if attributes.IsMain then
                        mainFile = file
                    end
                end
            end
        end
        response.close()

        if not mainFile then
            print("No main file found...")
        end
        runMain(mainFile, true) -- Retry/loop back into it repeatedly if it crashes
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
local function update()
    if not Startup_Method_Is_Second_Run then
        if not shouldUpdate() then return end
        updateStartup()
        Startup_Method_Is_Second_Run = true
        -- Run the updated startup script again... with our global set, it should now do the second pass
        runMain("startup")
        return
    end
    updateFiles()
end


-- Perform update
update()