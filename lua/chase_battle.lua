-- Chase Battle Plugin Client Script (v2.0)
-- Modular Architecture

-- Modules
local CB_Config = {}
local CB_Utils = {}
local CB_Admin = {}
local CB_Spectator = {}
local CB_Battle = {}
local CB_Visuals = {}
local CB_Network = {}

-- Global State
local car = ac.getCar(0)
local sessionTime = 0

------------------------------------------------------------------------
-- CB_Config: Configuration & Coordinate Parsing
------------------------------------------------------------------------
function CB_Config.Init()
    CB_Config.FinishPos = vec3(0,0,0)
    CB_Config.FinishFwd = vec3(0,0,1)
    CB_Config.ChasePos = vec3(0,0,0)
    CB_Config.ChaseFwd = vec3(0,0,1)
    
    -- Visual Lines (Calculated by Server)
    CB_Config.FinishLineA = vec3(0,0,0)
    CB_Config.FinishLineB = vec3(0,0,0)
    CB_Config.ChaseLineA = vec3(0,0,0)
    CB_Config.ChaseLineB = vec3(0,0,0)

    -- Load from Server Config
    -- Note: We expect these to be injected as global strings by C# plugin
    if ConfigFinishPos then CB_Config.FinishPos = CB_Config.ParseVec3(ConfigFinishPos) end
    if ConfigFinishFwd then CB_Config.FinishFwd = CB_Config.ParseVec3(ConfigFinishFwd) end
    if ConfigChasePos then CB_Config.ChasePos = CB_Config.ParseVec3(ConfigChasePos) end
    if ConfigChaseFwd then CB_Config.ChaseFwd = CB_Config.ParseVec3(ConfigChaseFwd) end

    if ConfigFinishLineA then CB_Config.FinishLineA = CB_Config.ParseVec3(ConfigFinishLineA) end
    if ConfigFinishLineB then CB_Config.FinishLineB = CB_Config.ParseVec3(ConfigFinishLineB) end
    if ConfigChaseLineA then CB_Config.ChaseLineA = CB_Config.ParseVec3(ConfigChaseLineA) end
    if ConfigChaseLineB then CB_Config.ChaseLineB = CB_Config.ParseVec3(ConfigChaseLineB) end
end

function CB_Config.ParseVec3(str)
    -- Expects "vec3(x, y, z)" format from C#
    local x, y, z = str:match("vec3%(([^,]+), ([^,]+), ([^,]+)%)")
    if x and y and z then
        return vec3(tonumber(x), tonumber(y), tonumber(z))
    end
    return vec3(0,0,0)
end

------------------------------------------------------------------------
-- CB_Utils: Helper Functions
------------------------------------------------------------------------
function CB_Utils.CheckPlaneCrossing(prevPos, currPos, planePos, planeFwd)
    -- Plane defined by Point(planePos) and Normal(planeFwd - planePos)
    local normal = (planeFwd - planePos):normalize()
    
    local distPrev = (prevPos - planePos):dot(normal)
    local distCurr = (currPos - planePos):dot(normal)

    -- Crossed if sign changed from negative (before) to positive (after)
    -- Assuming "Forward" points INTO the finish zone
    return distPrev < 0 and distCurr >= 0
end

------------------------------------------------------------------------
-- CB_Network: Protocol Handler
------------------------------------------------------------------------
function CB_Network.Init()
    -- Hook into ac.onChatMessage because we send as ChatMessages
    -- Format: CHASE_BATTLE:<OPCODE>:<PAYLOAD>
end

function CB_Network.ProcessMessage(msg)
    if not msg:find("^CHASE_BATTLE:") then return end
    
    local parts = {}
    for part in msg:gmatch("[^:]+") do table.insert(parts, part) end
    
    local opcode = parts[2]
    local payload = parts[3] or ""

    if opcode == "AUTH" then CB_Admin.SetAuth(payload == "TRUE")
    elseif opcode == "STATE" then CB_Battle.SetState(tonumber(payload))
    elseif opcode == "SETUP" then CB_Battle.SetContestants(payload)
    elseif opcode == "START" then CB_Battle.OnStart(payload)
    elseif opcode == "GO" then CB_Battle.OnGo()
    elseif opcode == "RESULT" then CB_Battle.OnResult(payload)
    end
end

------------------------------------------------------------------------
-- CB_Admin: Admin Panel
------------------------------------------------------------------------
CB_Admin.IsAdmin = false
CB_Admin.Drivers = { }
CB_Admin.SelectedLeader = -1
CB_Admin.SelectedChaser = -1
CB_Admin.RefreshTimer = 0

function CB_Admin.SetAuth(isAdmin)
    CB_Admin.IsAdmin = isAdmin
    if isAdmin then ac.log("ChaseBattle: Admin Access Granted") end
end

function CB_Admin.Update(dt)
    local sim = ac.getSim()
    local isAuthorized = CB_Admin.IsAdmin or sim.isAdmin
    
    -- Auto Refresh Drivers every 5s if authorized
    if isAuthorized then
        CB_Admin.RefreshTimer = CB_Admin.RefreshTimer + dt
        if CB_Admin.RefreshTimer > 5 then
            CB_Admin.RefreshDrivers()
            CB_Admin.RefreshTimer = 0
        end
    end
end

function CB_Admin.DrawAdminPanel()
    local sim = ac.getSim()
    local isAuthorized = CB_Admin.IsAdmin or sim.isAdmin

    -- Use ui.window to create an interactive standard panel
    ui.window("Chase Battle Admin", vec2(20, 100), vec2(300, 380), function()
        if not isAuthorized then
            ui.text("You are not currently authorized as Admin.")
            if ui.button("Check Admin Privileges") then
                ac.checkAdminPrivileges()
            end
            return
        end

        ui.text("Status: " .. CB_Battle.GetStateName())
        ui.SameLine()
        if ui.button("Force Refresh") then CB_Admin.RefreshDrivers() end
        
        ui.separator()
        
        -- Selection UI
        ui.text("LEADER: " .. (ac.getDriverName(CB_Admin.SelectedLeader) or "None"))
        ui.text("CHASER: " .. (ac.getDriverName(CB_Admin.SelectedChaser) or "None"))
        
        ui.separator()
        ui.text("Player List:")
        
        ui.beginChild("PlayerList", vec2(0, 150), true)
        for _, driver in ipairs(CB_Admin.Drivers) do
             ui.pushID(driver.id)
             if ui.button("L") then CB_Admin.SelectedLeader = driver.id end
             ui.SameLine()
             if ui.button("C") then CB_Admin.SelectedChaser = driver.id end
             ui.SameLine()
             
             local color = rgbm(1,1,1,1)
             if driver.id == CB_Admin.SelectedLeader then color = rgbm(0,1,0,1) end
             if driver.id == CB_Admin.SelectedChaser then color = rgbm(1,0,0,1) end
             ui.textColored(driver.name .. " ("..driver.id..")", color)
             
             ui.popID()
        end
        ui.endChild()

        ui.separator()
        
        if ui.button("SET CONTESTANTS", vec2(-1, 0)) then
            if CB_Admin.SelectedLeader ~= -1 and CB_Admin.SelectedChaser ~= -1 then
                 ac.sendChatMessage("/chase_cmd SET_ROLES " .. CB_Admin.SelectedLeader .. "," .. CB_Admin.SelectedChaser)
            else
                 ac.log("Please select both Leader and Chaser.")
            end
        end
        
        ui.separator()
        
        local startColor = rgbm(0,1,0,0.5)
        local stopColor = rgbm(1,0,0,0.5)
        
        ui.pushStyleColor(ui.StyleColor.Button, startColor)
        if ui.button("START BATTLE", vec2(130, 0)) then ac.sendChatMessage("/chase_cmd START") end
        ui.popStyleColor()
        
        ui.SameLine()
        
        ui.pushStyleColor(ui.StyleColor.Button, stopColor)
        if ui.button("STOP / RESET", vec2(130, 0)) then ac.sendChatMessage("/chase_cmd STOP") end
        ui.popStyleColor()
    end)
end

------------------------------------------------------------------------
-- Main Loop hooks (Called from footer)
------------------------------------------------------------------------

function script.update(dt)
    CB_Config.Update() -- Check if config reload needed (optional)
    
    CB_Admin.Update(dt)
    CB_Spectator.Update(dt)
    CB_Battle.Update(dt)
end

function script.draw3D(dt)
    CB_Visuals.DrawD3()
end

function script.drawUI(dt)
    CB_Admin.DrawAdminPanel()
    CB_Visuals.DrawHUD()
end

function CB_Config.Update()
    -- Optional: Hot reload checks if needed
end

------------------------------------------------------------------------
-- CB_Visuals: Rendering
------------------------------------------------------------------------
CB_Visuals.ResultText = ""
CB_Visuals.ResultTimer = 0

function CB_Visuals.ShowResult(winner, reason)
    local w = winner == "Leader" and "LEADER ESCAPED!" or "CHASER WINS!"
    if winner == "DRAW" then w = "DRAW!" end
    
    CB_Visuals.ResultText = w .. "\n" .. (reason or "")
    CB_Visuals.ResultTimer = 5
end

function CB_Visuals.DrawD3()
    -- Draw Finish Line (Green)
    if CB_Config.FinishLineA and CB_Config.FinishLineB then
         render.debugLine(CB_Config.FinishLineA, CB_Config.FinishLineB, rgbm(0,1,0,1))
    end
    
    -- Draw Chase Line (Red)
    if CB_Config.ChaseLineA and CB_Config.ChaseLineB then
         render.debugLine(CB_Config.ChaseLineA, CB_Config.ChaseLineB, rgbm(1,0,0,1))
    end
end

function CB_Visuals.DrawHUD()
    -- 1. Result Text (Big Center)
    if CB_Visuals.ResultTimer > 0 then
        CB_Visuals.ResultTimer = CB_Visuals.ResultTimer - 0.016 -- approx dt
        ui.pushFont(ui.Font.Title)
        local screen = ui.windowSize()
        -- Center text roughly
        ui.setCursor(vec2(screen.x / 2 - 200, screen.y / 2 - 100))
        ui.textColored(CB_Visuals.ResultText, rgbm(1,1,0,1))
        ui.popFont()
    end

    -- 2. State & Role (Top Left)
    -- Only show if involved or spec
    if CB_Battle.Role and CB_Battle.Role ~= "NONE" then
        ui.beginTransparentWindow("HubOverlay", vec2(100, 50), vec2(400, 100))
        ui.text("Role: " .. CB_Battle.Role)
        ui.text("State: " .. CB_Battle.GetStateName())
        
        -- Show Gap?
        if CB_Battle.State == 2 then
             local lCar = ac.getCar(CB_Battle.LeaderID)
             local cCar = ac.getCar(CB_Battle.ChaserID)
             if lCar and cCar then
                 local dist = ac.getDistance(lCar.position, cCar.position)
                 ui.text("Gap: " .. math.floor(dist) .. "m")
             end
        end
        ui.endTransparentWindow()
    end
end

function ac.onChatMessage(msg, senderName, senderId)
    -- Filter system messages
    if senderId == -1 or senderName == "Server" then
        CB_Network.ProcessMessage(msg)
    end
end

-- Init
CB_Config.Init()
