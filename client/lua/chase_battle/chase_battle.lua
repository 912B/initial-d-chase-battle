-- Chase Battle Client Script
-- Implements HUD, Spline Distance Calculation, and Win Condition Logic

local carLeader = nil
local carChaser = nil
local role = "SPECTATOR" -- "LEADER", "CHASER", "SPECTATOR"
local currentRound = 0
local battleActive = false

-- Config
local WIN_DISTANCE_M = 150
local CLAIM_DISTANCE_M = 10

-- Input Locking Logic
local inputLocked = false

function script.update(dt)
    -- Input Lock Override
    if inputLocked then
        ac.overrideCarState("gas", 0)
        ac.overrideCarState("brake", 1)
        ac.overrideCarState("clutch", 1)
        ac.overrideCarState("steer", 0)
        ac.overrideCarState("handbrake", 1)
    end

    if not battleActive then return end

    -- 1. Get Cars (Simplified for POC, normally requires ID matching)
    if not carLeader then carLeader = ac.getCar(0) end -- Assume Player is Leader for test
    if not carChaser then carChaser = ac.getCar(1) end -- Assume AI/Opponent is Chaser for test

    if not carLeader or not carChaser then return end

    -- 2. Calculate Distance (Spline Based)
    local leaderSpline = carLeader.splinePosition
    local chaserSpline = carChaser.splinePosition
    local trackLength = ac.getTrackLength()

    -- Handle wrap-around (if track is loop) - logic simplified for Touge (usually point-to-point)
    -- specific logic for looping tracks would be needed here if applicable.
    
    local distance = (leaderSpline - chaserSpline) * trackLength
    
    -- 3. Check End Conditions
    if distance > WIN_DISTANCE_M then
        -- Leader escaped
        ac.sendChatMessage("/chase report LEADER ESCAPE")
        battleActive = false
    elseif distance < -10 then -- Chaser is ahead (Overtake)
         -- Chaser Overtook
        ac.sendChatMessage("/chase report CHASER OVERTAKE")
        battleActive = false
    end
end

function script.drawUI()
    if not battleActive then return end
    
    local uiState = ac.getUiState()
    
    -- Draw Distance Bar
    local barWidth = 400
    local barHeight = 20
    local screenCenter = vec2(Screen.width / 2, 80)
    
    ui.drawRectFilled(screenCenter - vec2(barWidth/2, barHeight/2), screenCenter + vec2(barWidth/2, barHeight/2), rgbm(0, 0, 0, 0.5))
    
    -- Calculate Bar Fill
    -- Center is 0m. Left (Red) is Chaser gaining (distance < 0 or close to 0 from positive). Right (Blue) is Leader escaping.
    -- Let's map 0 to 150m to the right half.
    
    local currDist = (carLeader.splinePosition - carChaser.splinePosition) * ac.getTrackLength()
    local ratio = math.max(0, math.min(currDist / WIN_DISTANCE_M, 1))
    
    -- Draw Leader Zone (Blue)
    local fillWidth = (barWidth / 2) * ratio
    ui.drawRectFilled(screenCenter, screenCenter + vec2(fillWidth, barHeight/2), rgbm(0, 0, 1, 0.8))
    
    -- Text
    ui.pushFont(ui.Font.Title)
    ui.textAligned(string.format("%.1f m", currDist), screenCenter - vec2(0, 30), vec2(0.5, 0.5))
    ui.popFont()
    
    -- Draw Role Icon
    local roleText = role == "LEADER" and "LEAD" or (role == "CHASER" and "CHASE" or "SPEC")
    local roleColor = role == "LEADER" and rgbm(0, 0, 1, 1) or (role == "CHASER" and rgbm(1, 0, 0, 1) or rgbm(0.5, 0.5, 0.5, 1))
    
    ui.setCursor(vec2(50, Screen.height - 100))
    ui.pushStyleColor(ui.StyleColor.Text, roleColor)
    ui.text(roleText)
    ui.popStyleColor()

    -- Swap & Replay Notification
    if swapPending then
        ui.pushFont(ui.Font.Main)
        ui.textAligned("ROUND DRAW! SWAPPING POSITIONS...", vec2(Screen.width/2, Screen.height/2), vec2(0.5, 0.5))
        if ui.button("TELEPORT TO START") then
             ac.sendChatMessage("/chase teleport start") 
             -- Note: This command needs to be handled by server or extra_tweaks script
        end
        ui.popFont()
    end
end

-- Chat Message Handling
function ac.onChatMessage(message, author)
    if message:startsWith("CHASE_START:") then
        -- Format: CHASE_START: LeaderName(ID) vs ChaserName(ID)
        -- Simplified parsing for demo:
        battleActive = true
        swapPending = false
        -- logic to parse ID and set carLeader/carChaser
    elseif message:startsWith("CHASE_SWAP") then
        swapPending = true
        battleActive = false
        -- Logic to swap roles locally if needed immediately, or wait for next Start
    end
end

-- Teleport Logic (Client-Side Fallback)
function script.onConsoleCommand(command, args)
    if command == "teleport_start" then
        -- Try to find car root and move it
        -- Note: This is experimental and might reset physics state abruptly
        local carRoot = ac.findNodes('carRoot:0')
        if carRoot then
            carRoot:setPosition(vec3(0, 0, 0)) -- Replace with actual start coordinates
            ac.log("Teleported to start (0,0,0)")
        end
    elseif command == "lock_input" then
        inputLocked = not inputLocked
        ac.log("Input Locked: " .. tostring(inputLocked))
    end
end

-- Input Locking Logic
local inputLocked = false

function script.update(dt)
    if inputLocked then
        ac.overrideCarState("gas", 0)
        ac.overrideCarState("brake", 1)
        ac.overrideCarState("clutch", 1)
        ac.overrideCarState("steer", 0)
        -- Optional: Force Handbrake
        ac.overrideCarState("handbrake", 1)
    end

    if not battleActive then return end
