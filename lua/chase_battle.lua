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
    if not CB_Admin.IsAdmin and not sim.isAdmin then return end
    
    -- Auto Refresh Drivers every 5s
    CB_Admin.RefreshTimer = CB_Admin.RefreshTimer + dt
    if CB_Admin.RefreshTimer > 5 then
        CB_Admin.RefreshDrivers()
        CB_Admin.RefreshTimer = 0
    end
end

function script.windowMain(dt)
    local sim = ac.getSim()
    local isAuthorized = CB_Admin.IsAdmin or sim.isAdmin

    ui.window("Chase Battle Admin", vec2(20, 100), vec2(320, 380), function()
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

function CB_Admin.RefreshDrivers()
    CB_Admin.Drivers = {}
    for i = 0, ac.getSim().carsCount - 1 do
        local c = ac.getCar(i)
        if c and c.isConnected then
            table.insert(CB_Admin.Drivers, { id = i, name = ac.getDriverName(i) })
        end
    end
end

------------------------------------------------------------------------
-- CB_Spectator: Input Locking
------------------------------------------------------------------------
CB_Spectator.IsSpectating = false
CB_Spectator.TeleportTimer = 0

function CB_Spectator.Update(dt)
    if not CB_Spectator.IsSpectating then return end
    
    -- Only active during battle states (Countdown/Active)
    -- If Idle, spectators can roam? Spec implies "Not Contestant".
    -- If server sends SETUP, we are SPEC.
    -- We should only lock when State > 0.
    if CB_Battle.State == 0 then return end

    -- Lock Inputs
    ac.setDisplayMessage("Spectator Mode", "Battle in Progress - Controls Locked")
    
    -- Physics Lock
    ac.ext.physicsSetGas(0)
    ac.ext.physicsSetBrake(1)
    ac.ext.physicsSetClutch(1)
    ac.ext.physicsSetGear(0)
    ac.ext.physicsSetSteer(0)
    
    -- Force Pit Return logic (Optional: if user drives out, port back)
    -- For now, just Lock is sufficient as they can't drive.
    -- But if they were on track when battle started, they are stuck on track.
    -- Server should teleport them or we do it here.
    -- C# ChaseManager doesn't teleport spectators effectively (can't target easily).
    -- So Lua does it.
    
    -- If car is not in pitbox (velocity > 1 or distance from pit > 5m?), Teleport.
    -- Simplify: Just force camera to different view?
    -- Let's attempt to use ac.ext.teleportTo(pit) if possible.
    -- Or just rely on input lock. 
    -- User requirement: "传送回pit 并锁定油门".
    
    if CB_Spectator.TeleportTimer < 1.0 then -- Try teleport once at start of mode
        ac.sendChatMessage("/box") -- Server command to teleport to pit? 
        -- Or CSP:
        -- ac.ext.physicsSetCarPosition(...) to pit spawn?
        -- We don't know pit spawn easily.
        -- "/box" or "/pits" chat command is standard for some servers.
        -- AssettoServer might handle "/teleport_pit"?
        -- Let's assume Input Lock is the primary mechanism and the user accepts "stuck where they are" if teleport fails, 
        -- OR we rely on a standard AC function if available. 
        -- `ac.returnToPit()` exists in some CSP versions? 
        -- Let's try `ac.sendChatMessage("/mid-race-spectate")` if server supports it.
        
        -- Fallback: Just lock.
        CB_Spectator.TeleportTimer = CB_Spectator.TeleportTimer + dt
    end
end

------------------------------------------------------------------------
-- CB_Battle: Core Logic
------------------------------------------------------------------------
CB_Battle.State = 0 -- 0:Idle, 1:Countdown, 2:Active, 3:Finished
CB_Battle.Role = "NONE" -- LEAD, CHASE, SPEC
CB_Battle.LeaderID = -1
CB_Battle.ChaserID = -1

-- State Tracking
CB_Battle.LastPosLeader = vec3(0,0,0)
CB_Battle.LastPosChaser = vec3(0,0,0)
CB_Battle.ChaserCrossedLine = false

function CB_Battle.SetState(s) 
    CB_Battle.State = s 
    if s == 0 then
        CB_Battle.ChaserCrossedLine = false
    end
end

function CB_Battle.GetStateName() 
    local names = { [0]="Idle", [1]="Countdown", [2]="Active", [3]="Finished" }
    return names[CB_Battle.State] or "Unknown"
end

function CB_Battle.SetContestants(payload)
    local lId, cId = payload:match("([^,]+),([^,]+)")
    CB_Battle.LeaderID = tonumber(lId)
    CB_Battle.ChaserID = tonumber(cId)
    
    local myId = car.index
    if myId == CB_Battle.LeaderID then CB_Battle.Role = "LEAD"
    elseif myId == CB_Battle.ChaserID then CB_Battle.Role = "CHASE"
    else CB_Battle.Role = "SPEC" end
    
    CB_Spectator.IsSpectating = (CB_Battle.Role == "SPEC")
    
    -- Log Role for Debug
    if CB_Battle.Role ~= "SPEC" then
        ac.log("Chase Battle Role Assigned: " .. CB_Battle.Role)
    end
end

function CB_Battle.OnStart(gridIndex)
    -- Teleport logic
    -- Grid 0: Leader, Grid 1: Chaser
    -- Or reverse depending on track config? usually Leader in front.
    local myGrid = -1
    if CB_Battle.Role == "LEAD" then myGrid = 0
    elseif CB_Battle.Role == "CHASE" then myGrid = 1 end
    
    if myGrid ~= -1 then
        -- Use CSP teleport if available, or reset to pit then move?
        -- physics.teleportTo is not standard Lua API but standard Assetto usually allows "restart".
        -- Server probably handles the restart logic or we need to teleport manually.
        -- Assuming "START" signal implies we should be at start.
        -- Since we can't easily teleport in standard Lua without CSP extension `physics.setCarPosition`, we rely on that.
        -- If `ac.ext` is available:
        if ac.ext and ac.ext.physicsSetCarPosition then
             -- We need spawn positions. 
             -- Valid approach: ac.getSpawnPosition(gridIndex)
             -- Need to verify API. ac.getSpawnPoint(index) exists!
             local spawn = ac.getSpawnPoint(myGrid)
             ac.ext.physicsSetCarPosition(car.index, spawn.position, spawn.look, spawn.up)
             ac.ext.physicsSetVelocity(car.index, vec3(0,0,0), vec3(0,0,0))
        end
    end
    
    -- Lock Input
    CB_Battle.InputLocked = true
end

function CB_Battle.OnGo()
    CB_Battle.InputLocked = false
    ac.sendChatMessage("GO! GO! GO!")
end

function CB_Battle.OnResult(payload)
    local winner, reason = payload:match("([^,]+),([^,]+)")
    ac.log("Battle Result: " .. (winner or "") .. " Reason: " .. (reason or ""))
    -- Show UI notification (Big Text)
    CB_Visuals.ShowResult(winner, reason)
end

function CB_Battle.Update(dt)
    -- Input Lock Handling for Contestants
    if CB_Battle.InputLocked then
        ac.ext.physicsSetGas(0)
        ac.ext.physicsSetBrake(1)
        ac.ext.physicsSetClutch(1)
        ac.ext.physicsSetGear(0)
        return -- Skip logic if locked
    end

    if CB_Battle.State ~= 2 then return end -- Only Active
    
    -- We need positions of BOTH cars.
    -- In Client Lua, getting opponent position requires `ac.getCar(id)`
    local leaderCar = ac.getCar(CB_Battle.LeaderID)
    local chaserCar = ac.getCar(CB_Battle.ChaserID)
    
    if not leaderCar or not chaserCar then return end
    
    -- We assume `script.update` calls this, so `car` global is MY car.
    -- Logic runs on both clients independently? 
    -- Ideally logic runs on Leader or Chaser or Both and reports.
    -- To avoid double reporting, usually Leader reports win/loss, or both do.
    -- Server handles deduplication.
    
    -- Let's run logic on EVERYONE involved (Leader/Chaser)
    if CB_Battle.Role == "SPEC" then return end

    local lPos = leaderCar.position
    local cPos = chaserCar.position
    
    -- 0. Update Last Pos (Initial)
    if CB_Battle.LastPosLeader == vec3(0,0,0) then CB_Battle.LastPosLeader = lPos end
    if CB_Battle.LastPosChaser == vec3(0,0,0) then CB_Battle.LastPosChaser = cPos end

    -- 1. Check Overtake (Chaser Wins if ahead of Leader by > 5m? No, just ahead)
    -- "Distance < -5m (Chaser in front)"
    -- We calculate Spline Dist
    local lSpline = leaderCar.splinePosition
    local cSpline = chaserCar.splinePosition
    
    -- Correct Spline wrapping if needed (Track loop)
    if lSpline < 0.1 and cSpline > 0.9 then lSpline = lSpline + 1 end
    
    local splineGap = (lSpline - cSpline) 
    -- Approximate gap in meters (Need track length? ac.getTrackLength())
    local trackLen = ac.getTrackLength()
    local gapM = splineGap * trackLen
    
    if gapM < -5 then
         -- Chaser is 5m ahead of Leader -> Chaser WIN
         ac.sendChatMessage("/chasereport WIN") 
         CB_Battle.State = 3 -- Prevent double report locally
         return
    end
    
    -- 2. Check Chase Line Crossing (Chaser)
    local chaserCrossed = CB_Utils.CheckPlaneCrossing(CB_Battle.LastPosChaser, cPos, CB_Config.ChasePos, CB_Config.ChaseFwd)
    if chaserCrossed then
        CB_Battle.ChaserCrossedLine = true
        ac.log("Chaser Crossed Chase Line!")
    end

    -- 3. Check Finish Line Crossing (Leader)
    local leaderFinished = CB_Utils.CheckPlaneCrossing(CB_Battle.LastPosLeader, lPos, CB_Config.FinishPos, CB_Config.FinishFwd)
    
    if leaderFinished then
        ac.log("Leader Finished!")
        -- Leader reached finish. Check Chaser status.
        if CB_Battle.ChaserCrossedLine then
             -- Chaser already crossed Chase Line -> DRAW
             ac.sendChatMessage("/chasereport DRAW")
        else
             -- Chaser NOT crossed Chase Line -> Leader Wins (Escape)
             ac.sendChatMessage("/chasereport LOSS") 
        end
        CB_Battle.State = 3
    end

    -- Update Last Pos
    CB_Battle.LastPosLeader = lPos
    CB_Battle.LastPosChaser = cPos
end

------------------------------------------------------------------------
-- Main Loop hooks (Called from footer)
------------------------------------------------------------------------

function script.update(dt)
    CB_Config.Update() -- Check if config reload needed (optional)
    
    CB_Admin.Update(dt)
    CB_Spectator.Update(dt)
    CB_Battle.Update(dt)
    
    -- Visuals
    CB_Visuals.DrawD3()
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
    if CB_Battle.Role ~= "NONE" then
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
