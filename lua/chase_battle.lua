-- Chase Battle Client Script
-- Implements HUD, Spline Distance Calculation, Win Condition Logic and Leaderboard Challenge
-- Styled for Initial D aesthetics

local carLeader = nil
local carChaser = nil
local role = "SPECTATOR" -- "LEADER", "CHASER", "SPECTATOR"
local battleActive = false
local battleOpponentName = ""

-- UI State
local isWaitingForServer = false -- Prevent double clicking VS button
local startLapLeader = 0
local startLapChaser = 0

-- Config
local WIN_DISTANCE_M = 150
local CLAIM_DISTANCE_M = 10

-- Input Locking Logic
local inputLocked = false
-- Countdown Logic
local countdownActive = false
local countdownTimer = 0
local countdownFreezePos = nil
local countdownFreezeLook = nil
local countdownFreezeUp = nil

-- prevMouseDown handled inside drawLeaderboard logic via simple state if needed, or global.
local prevMouseDown = false
local lastClickDebug = "None"

-- Colors (Initial D Style)
local colYellow = rgbm(1, 1, 0, 1)      -- Main Text
local colBlackBG = rgbm(0, 0, 0, 0.7)   -- Background
local colRed = rgbm(1, 0, 0, 1)         -- Highlight/Battle
local colWhite = rgbm(1, 1, 1, 1)       -- Standard Text
local colGreen = rgbm(0, 1, 0, 1)       -- GO signal

-- Chat Message Handling Logic (Separated for Simulation)
-- Defined early so it can be called by UI functions
local function handleChaseMessage(message, author)
    if message:find("CHASE_START:") then
        ac.log("Received CHASE_START raw: " .. message)
        -- Identify IDs
        local l_id, c_id = message:match("CHASE_START:%s*(%d+)%s*vs%s*(%d+)")
        
        if l_id and c_id then
            local leaderId = tonumber(l_id)
            local chaserId = tonumber(c_id)
            local myId = ac.getSim().focusedCar
            
            ac.log("CHASE_START Signal: " .. leaderId .. " vs " .. chaserId .. ". Me=" .. tostring(myId))
            
            -- Resolve cars by Server Slot
            local leaderCarObj = ac.getCar.serverSlot(leaderId)
            local chaserCarObj = ac.getCar.serverSlot(chaserId)

            -- Fallback for Offline/Simulation if ServerSlot returns nil
            if not leaderCarObj and (leaderId == 0 or leaderId == 999) then leaderCarObj = ac.getCar(0) end
            if not chaserCarObj and (chaserId == 0 or chaserId == 999) then chaserCarObj = ac.getCar(0) end

            if leaderCarObj and chaserCarObj then
                ac.log("Resolved Cars: L="..tostring(leaderCarObj.index) .. " C="..tostring(chaserCarObj.index).. " Me="..tostring(myId))
                
                if tonumber(myId) == tonumber(leaderCarObj.index) then
                    carLeader = leaderCarObj
                    carChaser = chaserCarObj
                    role = "LEADER"
                    battleActive = true
                    local dName = carChaser.driverName
                    if type(dName) == "function" then dName = dName(carChaser) end
                    battleOpponentName = dName
                    ac.log("Battle Started: You are LEADER. Teleporting to Grid 1...")
                    ui.toast(ui.Icons.Confirm, "BATTLE START! (Leader)")
                    battleOpponentName = dName
                    ac.log("Battle Started: You are LEADER. Teleporting to Grid 1...")
                    ui.toast(ui.Icons.Confirm, "BATTLE START! (Leader)")
                    isWaitingForServer = false -- Reset waiting state
                    teleportToGrid(1)
                elseif tonumber(myId) == tonumber(chaserCarObj.index) then
                    carLeader = leaderCarObj
                    carChaser = chaserCarObj
                    role = "CHASER"
                    battleActive = true
                    local dName = carLeader.driverName
                    if type(dName) == "function" then dName = dName(carLeader) end
                    battleOpponentName = dName
                     ac.log("Battle Started: You are CHASER. Teleporting to Grid 0...")
                     ui.toast(ui.Icons.Confirm, "BATTLE START! (Chaser)")
                     ac.log("Battle Started: You are CHASER. Teleporting to Grid 0...")
                     ui.toast(ui.Icons.Confirm, "BATTLE START! (Chaser)")
                     isWaitingForServer = false -- Reset waiting state
                     teleportToGrid(0)
                else
                    ac.log("Chase Msg received but not involved (Me="..tostring(myId)..")")
                end
            else
                 local errMsg = "Error resolving cars: L=" .. tostring(leaderCarObj) .. " C=" .. tostring(chaserCarObj)
                 ac.log(errMsg)
            end
        else
            ac.log("Failed to parse IDs from CHASE_START: " .. message)
        end
    end
    -- CHASE_END logic would go here if needed
end

function script.update(dt)
    if not _logTestDone then
        ac.log("LUA_LOG_TEST: Script update loop is running.")
        _logTestDone = true
    end

    -- Countdown & Input Lock (Freeze Method)
    if countdownActive then
        countdownTimer = countdownTimer - dt
        -- Force car to stay at spawn position
        if countdownTimer > 0 and countdownFreezePos and countdownFreezeLook and countdownFreezeUp then
             local car = ac.getCar(ac.getSim().focusedCar)
             if car and physics and physics.setCarPosition then
                 physics.setCarPosition(car.index, countdownFreezePos, countdownFreezeLook, countdownFreezeUp)
                 if physics.setCarVelocity then
                     physics.setCarVelocity(car.index, vec3(0,0,0))
                 end
             end
        elseif countdownTimer < -2 then
             -- End countdown state after "GO" has shown for 2 seconds
             countdownActive = false
             countdownFreezePos = nil -- formatting cleanup
        end
    end

    if not battleActive then return end

    if not carLeader or not carChaser then return end

    -- 2. Calculate Distance (Spline Based)
    local leaderSpline = carLeader.splinePosition
    local chaserSpline = carChaser.splinePosition
    
    local sim = ac.getSim()
    local trackLength = sim.trackLengthM or 5000


    -- Simple distance for point-to-point/Touge
    -- If loop track support is needed, checking (0.9 vs 0.1) wrap-around is required
    local distance = (leaderSpline - chaserSpline) * trackLength
    
    -- 3. Check End Conditions
    -- Avoid instant finish if cars are spawned at strange locations (sanity check distance < trackLength/2)
    if math.abs(distance) < trackLength / 2 then
        if distance > WIN_DISTANCE_M then
            -- Leader escaped
            ac.sendChatMessage("/chasereport LOSS") -- Leader Escaped = Chaser Loss
            -- Local reset handled by CHASE_END broadcast
        elseif distance < -5 then -- Chaser is ahead (Overtake) 
             -- Chaser Overtook
            ac.sendChatMessage("/chasereport WIN") -- Chaser Overtook = Chaser Win
            -- Local reset handled by CHASE_END broadcast
        elseif (carLeader.lapCount > startLapLeader) or (carChaser.lapCount > startLapChaser) or (leaderSpline > 0.99) or (chaserSpline > 0.99) then
             -- Reached Finish Line (Lap or Spline) -> DRAW
            ac.sendChatMessage("/chasereport DRAW")
        end
    end
end

function script.drawUI()
    local uiState = ac.getUiState()
    
    -- 1. Draw Battle HUD (if active)
    if battleActive and carLeader and carChaser then
        drawBattleHUD(uiState)
    elseif battleActive then
        -- Debug: Why is HUD not drawing if battle is active?
        -- Rate limit logs
        if math.random() < 0.01 then 
            ac.log("UI_DEBUG: Battle Active but Cars Nil? Leader="..tostring(carLeader).." Chaser="..tostring(carChaser)) 
        end
    end

    -- 2. Draw Leaderboard (Always visible or toggleable? Keeping always visible for now)
    drawLeaderboard(uiState)

    -- Temporary Teleport Test
    ui.transparentWindow("Teleport Test", vec2(600, 100), vec2(150, 100), true, true, function()
        if ui.button("Test TP Grid 0") then
            teleportToGrid(0)
        end
        if ui.button("Test TP Grid 1") then
            teleportToGrid(1)
        end
    end)

    -- 3. Draw Countdown Overlay
    if countdownActive then
        drawCountdown(uiState)
    end
    if countdownActive then
        drawCountdown(uiState)
    end
end

-- Fallback Draw Listener
if ac.onDrawUI then
    ac.onDrawUI(script.drawUI)
end

function drawCountdown(uiState)
    local timer = math.ceil(countdownTimer)
    local text = ""
    local color = colRed

    if timer > 0 then
        text = tostring(timer)
    else
        text = "GO!"
        color = colGreen
    end

    -- Center Text
    ui.pushFont(ui.Font.Huge)
    local textSize = ui.measureText(text)
    local pos = (uiState.windowSize - textSize) / 2
    -- Adjust for upper center
    pos.y = uiState.windowSize.y * 0.3 

    ui.setCursor(pos)
    ui.pushStyleColor(ui.StyleColor.Text, color)
    ui.text(text)
    ui.popStyleColor()
    ui.popFont()
end

function drawBattleHUD(uiState)
    -- Design Constants
    local screenWidth = uiState.windowSize.x
    local screenHeight = uiState.windowSize.y
    local barWidth = 600
    local barHeight = 20
    local topMargin = 50
    
    local roleColor = colWhite
    local roleText = role
    
    if role == "LEADER" then 
        roleColor = colYellow
        roleText = "DOWNHILL SPECIALIST (LEADER)"
    elseif role == "CHASER" then
        roleColor = colRed
        roleText = "CHALLENGER (CHASER)"
    end
    
    -- 1. Role & Opponent Info (Top Center)
    ui.pushFont(ui.Font.Title)
    local roleSize = ui.measureText(roleText)
    ui.setCursor(vec2((screenWidth - roleSize.x) / 2, topMargin))
    ui.pushStyleColor(ui.StyleColor.Text, roleColor)
    ui.text(roleText)
    ui.popStyleColor()
    ui.popFont()
    
    ui.pushFont(ui.Font.Main)
    local vsText = "VS  " .. battleOpponentName
    local vsSize = ui.measureText(vsText)
    ui.setCursor(vec2((screenWidth - vsSize.x) / 2, topMargin + 30))
    ui.text(vsText)
    ui.popFont()

    -- 2. Distance Bar (C.A. Meter Style)
    -- Calculate Distance for UI
    local leaderSpline = carLeader.splinePosition
    local chaserSpline = carChaser.splinePosition
    local sim = ac.getSim()
    local trackLength = sim.trackLengthM or 5000
    -- Simple distance (Touge/Linear)
    local distance = (leaderSpline - chaserSpline) * trackLength
    
    -- Draw The Bar
    local barY = topMargin + 70
    local barX = (screenWidth - barWidth) / 2
    
    -- Background
    ui.drawRectFilled(vec2(barX, barY), vec2(barX + barWidth, barY + barHeight), colBlackBG, 0)
    
    -- Center Marker (0m / Overtake)
    local centerX = barX + (barWidth / 2) -- Keep 0 at center? Or 0 at left?
    -- Initial D Arcade usually has "Gap" bar. Let's do: 
    -- Left = Chaser Ahead (Negative Dist), Right = Leader Ahead (Positive Dist)
    -- Range: -50m to +150m (Win)
    
    local maxDist = WIN_DISTANCE_M -- 150m
    local range = maxDist + 50 -- Total range 200m (-50 to 150)
    -- Map distance to X. 
    -- 0m should be at some point. Let's say 25% is 0 (since chaser rarely gets far ahead without winning)
    -- Actually, simpler: 0 is Left edge, 150 is Right edge. If <0, it clamps to left. 
    -- But we want to show overtake danger. 
    -- Let's stick to standard: 0m = Left (Danger), 150m = Right (Safe for Leader)
    
    local progress = math.clamp(distance / maxDist, 0, 1) 
    
    -- Bar Color Logic
    local barCol = colYellow
    if distance < 20 then barCol = colRed -- Danger Zone / Close Battle
    elseif distance > 100 then barCol = colGreen -- Safe Zone
    end
    
    -- Fill
    ui.drawRectFilled(vec2(barX, barY), vec2(barX + (barWidth * progress), barY + barHeight), barCol, 0)
    
    -- Markers
    ui.drawLine(vec2(barX, barY - 5), vec2(barX, barY + barHeight + 5), colWhite, 2) -- 0m
    ui.drawLine(vec2(barX + barWidth, barY - 5), vec2(barX + barWidth, barY + barHeight + 5), colWhite, 2) -- Max
    
    -- Text Labels
    ui.pushFont(ui.Font.Main)
    ui.setCursor(vec2(barX, barY + barHeight + 5))
    ui.text("0m")
    
    ui.setCursor(vec2(barX + barWidth - 40, barY + barHeight + 5))
    ui.text(tostring(maxDist).."m")
    
    -- Current Dist Text centered on Bar
    local distText = string.format("%.1fm", distance)
    local dSize = ui.measureText(distText)
    ui.setCursor(vec2(barX + (barWidth * progress) - (dSize.x / 2), barY - 25))
    ui.text(distText)
    ui.popFont()
end

local leaderboardPos = vec2(50, 100)
local isDragging = false

function drawLeaderboard(uiState)
    -- GT2 Style Leaderboard (Custom Draggable)
    local width = 300
    local rowHeight = 32
    local headerHeight = 40
    
    -- Init Pos
    if leaderboardPos.x == 50 and leaderboardPos.y == 100 and uiState.windowSize.x > 0 then
         leaderboardPos = vec2(uiState.windowSize.x - width - 20, 100)
    end
    
    -- Colors
    local colPurple = rgbm(0.6, 0.0, 0.8, 1) -- Purple for header/badges
    local colRowBg = rgbm(0, 0, 0, 0.6)  -- Dark semi-transparent background
    local colText = rgbm(1, 1, 1, 1)
    
    -- Prepare Data
    local sim = ac.getSim()
    local displayCars = {}
    for i = 0, sim.carsCount - 1 do
        local c = ac.getCar.serverSlot(i)
        if c and c.isConnected then 
            -- Debug ID mapping: i is the Server Slot ID
            local dName = c.driverName
            if type(dName) == "function" then dName = dName(c) end
            -- ac.log("Leaderboard: Slot=" .. i .. " Name=" .. tostring(dName))
            -- Store both car and original server slot ID
            table.insert(displayCars, { car = c, slot = i }) 
        end
    end
    
    -- MOCK DATA FOR TESTING (Remove or set false in production)
    local TEST_MODE = false 
    if TEST_MODE then
        table.insert(displayCars, { index = 86, driverName = "Takumi Fujiwara", isConnected = true, splinePosition = 0.5 })
        table.insert(displayCars, { index = 7,  driverName = "Keisuke Takahashi", isConnected = true, splinePosition = 0.4 })
    end

    local contentHeight = headerHeight + (#displayCars * rowHeight) + 10

    -- Window Wrapper
    -- ui.transparentWindow(id, pos, size, noPadding, inputs, content)
    ui.transparentWindow("Leaderboard", leaderboardPos, vec2(width, contentHeight), true, true, function()
        
        -- Header Drag Logic (Global Coords Check, but updates global pos)
        local startX = leaderboardPos.x
        local startY = leaderboardPos.y
        local mPos = uiState.mousePos
        
        -- Check collision with Header area (Global Screen Space)
        if mPos and mPos.x >= startX and mPos.x <= (startX + width) and 
           mPos.y >= startY and mPos.y <= (startY + headerHeight) then
            ui.setTooltip("Hold to Move")
            if ui.mouseDown(0) then
                if ui.getMouseDelta then
                    leaderboardPos = leaderboardPos + ui.getMouseDelta()
                elseif uiState.mouseDelta then
                     leaderboardPos = leaderboardPos + uiState.mouseDelta
                end
                -- Update local vars for this frame's drawing
                startX = leaderboardPos.x
                startY = leaderboardPos.y
            end
        end

        -- Header Visuals (Global Coords for drawRectFilled)
        ui.drawRectFilled(vec2(startX, startY), vec2(startX + width, startY + headerHeight), colPurple, 0)
        
        -- Header Text (Relative Cursor to Window)
        -- Window content starts at 0,0 relative to window position.
        
        -- Note: We are using ui.drawRectFilled with GLOBAL coordinates (startX/Y) because that's how CSP drawing usually works
        -- regardless of window context unless using window draw list.
        -- But ui.text / ui.button use Layout coordinates (Relative).
        
        ui.setCursor(vec2(0, 5)) 
        ui.pushFont(ui.Font.Title)
        
        local headerText = "TOUGE BATTLE"
        local textSize = ui.measureText(headerText)
        ui.setCursor(vec2((width - textSize.x) / 2, 8))
        ui.text(headerText)
        ui.popFont()
        
        -- List
        local currentY_rel = headerHeight
        local rank = 1
        
        ui.pushFont(ui.Font.Main)
        
        for _, item in ipairs(displayCars) do
         local car = item.car
         if car then
                local currentY_abs = startY + currentY_rel
                
                -- Row BG (Absolute)
                ui.drawRectFilled(vec2(startX, currentY_abs), vec2(startX + width, currentY_abs + rowHeight), colRowBg, 0)
                
                -- Rank
                ui.setCursor(vec2(10, currentY_rel + 6))
                ui.text(tostring(rank))
                
                -- Badge (Absolute Box)
                local badgeSize = 24
                local badgeX_abs = startX + 35
                local badgeY_abs = currentY_abs + 4
                ui.drawRectFilled(vec2(badgeX_abs, badgeY_abs), vec2(badgeX_abs + badgeSize, badgeY_abs + badgeSize), colPurple, 4)
                
                local numStr = tostring(car.index)
                local numSize = ui.measureText(numStr)
                ui.setCursor(vec2(35 + (badgeSize - numSize.x)/2, currentY_rel + 4 + (badgeSize - numSize.y)/2))
                ui.text(numStr)
                
                -- Name
                local dName = car.driverName
                if type(dName) == "function" then dName = dName(car) end
                dName = tostring(dName)
                local nameSize = ui.measureText(dName)
                ui.setCursor(vec2(70, currentY_rel + (rowHeight - nameSize.y)/2))
                
                local isMe = (tonumber(car.index) == tonumber(sim.focusedCar))
                
                if isMe then ui.pushStyleColor(ui.StyleColor.Text, colYellow) end
                ui.text(dName)
                if isMe then ui.popStyleColor() end
                
                -- Status / Button
                local statusText = "-:--:---"
                local statusCol = colText
                local showButton = false
                
                if car.index == (carLeader and carLeader.index) or car.index == (carChaser and carChaser.index) then
                     statusText = "BATTLE"
                     statusCol = colRed
                elseif battleActive and isMe then
                     statusText = "BATTLE"
                     statusCol = colRed
                elseif isWaitingForServer and isMe then
                     statusText = "WAIT..."
                     statusCol = colYellow
                elseif not battleActive then
                     statusText = "FREE"
                     statusCol = rgbm(0,1,0,1)
                     if not isMe then showButton = true end
                end
                
                if showButton then
                    local btnWidth = 50
                    local btnHeight = 22
                    local btnX_rel = width - btnWidth - 5
                    local btnY_rel = currentY_rel + (rowHeight - btnHeight)/2
                    
                    ui.setCursor(vec2(btnX_rel, btnY_rel))
                    
                    -- Button Style
                    ui.pushStyleColor(ui.StyleColor.Button, rgbm(0.6, 0, 0, 1))
                    ui.pushStyleColor(ui.StyleColor.ButtonHovered, rgbm(0.8, 0, 0, 1))
                    ui.pushStyleColor(ui.StyleColor.ButtonActive, rgbm(1, 0, 0, 1))
                    
                    -- Use native ui.button
                    if ui.button("VS##"..item.slot, vec2(btnWidth, btnHeight)) then
                         if not isWaitingForServer then
                             -- Action: Challenge
                             isWaitingForServer = true
                             local cmd = "/chase " .. item.slot
                             ac.sendChatMessage(cmd)
                             ui.toast(ui.Icons.Confirm, "Request Sent...")
                             
                             -- Timeout reset (failsafe)
                             setTimeout(function() isWaitingForServer = false end, 5000)
                         end
                    end
                    ui.popStyleColor(3)

                else
                    local timeSize = ui.measureText(statusText)
                    ui.setCursor(vec2(width - timeSize.x - 10, currentY_rel + (rowHeight - timeSize.y)/2))
                    ui.pushStyleColor(ui.StyleColor.Text, statusCol)
                    ui.text(statusText)
                    ui.popStyleColor()
                end
                
                currentY_rel = currentY_rel + rowHeight
                rank = rank + 1
             end
        end
        ui.popFont()
    -- Debug Buttons at bottom
    local btnY = headerHeight + (#displayCars * rowHeight) + 10
    ui.setCursor(vec2(10, btnY))
    if ui.button("TP Grid 0") then teleportToGrid(0) end
    ui.sameLine()
    if ui.button("TP Grid 1") then teleportToGrid(1) end

    ui.transparentWindow("Teleport Test", vec2(600, 100), vec2(250, 140), true, true, function()
        ui.text("Debug Window")
        if ui.button("TP Grid 0") then teleportToGrid(0) end
        ui.sameLine()
        if ui.button("TP Grid 1") then teleportToGrid(1) end
        
        ui.newLine()
        ui.text("Simulation Test")
        if ui.button("Simulate: Be Leader") then
             ui.toast(ui.Icons.Settings, "Simulating Leader...")
             local mySimCar = ac.getCar(ac.getSim().focusedCar)
             local mySlot = 0 -- Default to 0 for offline sim
             for i, c in ac.iterateCars.serverSlots() do
                 if c.index == mySimCar.index then mySlot = i break end
             end
             
             local msg = string.format("CHASE_START: %d vs 999", mySlot)
             handleChaseMessage(msg, "System")
        end
        
        if ui.button("Simulate: Be Chaser") then
             ui.toast(ui.Icons.Settings, "Simulating Chaser...")
             local mySimCar = ac.getCar(ac.getSim().focusedCar)
             local mySlot = 0 
             for i, c in ac.iterateCars.serverSlots() do
                 if c.index == mySimCar.index then mySlot = i break end
             end
             
             local msg = string.format("CHASE_START: 999 vs %d", mySlot)
             handleChaseMessage(msg, "System")
        end
    end)
    
    end)
    
    prevMouseDown = ui.mouseDown(0)
end

-- Startup Toast
local initToastShown = false
if not initToastShown then
    ui.toast(ui.Icons.Settings, "Chase Battle Script Loaded")
    initToastShown = true
end

-- Chat Message Handling Logic (Separated for Simulation)


-- Bind to script event (Original)
function script.onChatMessage(message, author)
    ac.log("LUA_DEBUG: script.onChatMessage triggered. Msg='" .. message .. "'")
    handleChaseMessage(message, author)
    checkChaseEnd(message)
end

-- Bind to global event (Alternative 1)
function onChatMessage(message, author)
    ac.log("LUA_DEBUG: global onChatMessage triggered. Msg='" .. message .. "'")
    handleChaseMessage(message, author)
    checkChaseEnd(message)
end

-- Bind using ac.onChatMessage if available (Alternative 2)
if ac.onChatMessage then
    ac.onChatMessage(function(message, author)
        ac.log("LUA_DEBUG: ac.onChatMessage triggered. Msg='" .. message .. "'")
        handleChaseMessage(message, author)
        checkChaseEnd(message)
    end)
end

function checkChaseEnd(message)
    if message:find("CHASE_END") then
        local l_id_str = message:match("CHASE_END:%s*(%d+)")
        local l_id = tonumber(l_id_str)
        if l_id then
            if battleActive and carLeader and carLeader.index == l_id then endBattle() end
        else
            if battleActive then endBattle() end
        end
    end
end



function endBattle()
    battleActive = false
    carLeader = nil
    carChaser = nil
    role = "SPECTATOR"
    battleOpponentName = ""
    ac.log("Battle Ended")
end

function teleportToGrid(gridIndex)
    local nodeName = "AC_START_" .. gridIndex
    ac.log("TELEPORT DEBUG: Attempting teleport to " .. nodeName)
    
    local car = ac.getCar(ac.getSim().focusedCar)
    if not car then 
        ac.log("TELEPORT DEBUG: Car object not found")
        return 
    end

    if not car.physicsAvailable then
        ac.log("TELEPORT DEBUG: Car physics NOT available (physicsAvailable=false)")
        return
    end

    -- Try to find the specific spawn node for this grid index (e.g. AC_START_0, AC_START_1)
    -- This is better for curved tracks as the track author placed them correctly.
    local node = ac.findNodes(nodeName) 
    local useFallback = false

    if not node then
        ac.log("TELEPORT DEBUG: Node " .. nodeName .. " missing. Trying fallback to AC_START_0")
        node = ac.findNodes("AC_START_0") 
        useFallback = true
    end
    
    if node then
        -- Use Raw transform as standard one returns nil/is missing
        local matrix = node:getWorldTransformationRaw() 
        if matrix then
             -- Access fields directly
             local position = matrix.position
             local nodeLook = matrix.look      -- The node's alignment
             local up = matrix.up

             if not position then 
                 ac.log("TELEPORT DEBUG: Position vector is nil")
                 ac.sendChatMessage("/chasereport ERROR_POS_NIL")
                 return 
             end
             
             -- 1. Orientation: User confirmed "Reversed is correct" for direction.
             local carLook = -nodeLook 

             -- 2. Position: 
             -- If we found the specific node (e.g. AC_START_1), use its position directly.
             -- If we are using Fallback (AC_START_0 for everyone), THEN calculate offset.
             if useFallback and gridIndex > 0 then
                 -- Tandem Offset: Move BACKWARDS along the CAR'S LOOK vector.
                 -- If carLook is Downhill, -carLook is Uphill (Behind).
                 position = position - carLook * (14 * gridIndex) 
                 ac.log(string.format("TELEPORT DEBUG: Calculated Fallback Pos (Behind) for Index %d", gridIndex))
             else
                 ac.log(string.format("TELEPORT DEBUG: Using Native Node Pos for Index %d", gridIndex))
             end

             -- Raycast to ensure we are on ground
             local groundY = physics.raycastTrack(position + vec3(0, 2, 0), vec3(0, -1, 0), 10)
             if groundY ~= -1 then
                 position.y = position.y + 2 - groundY
             end
             
             -- Occupancy Check: Ensure no other car is at the target position
             local sim = ac.getSim()
             for i = 0, sim.carsCount - 1 do
                 if i ~= car.index then
                     local otherCar = ac.getCar(i)
                     if otherCar and otherCar.isConnected then
                          local dist = math.distance(otherCar.position, position)
                          if dist < 5.0 then -- 5 meters safety radius
                              ac.log(string.format("TELEPORT DEBUG: Spawn Occupied by Car %d (Dist: %.2f)", i, dist))
                              ui.toast(ui.Icons.Warning, "Spawn point occupied! Retrying...")
                              ac.sendChatMessage("/chasereport ERROR_OCCUPIED")
                              return
                          end
                     end
                 end
             end
             
             if physics and physics.setCarPosition then
                 physics.setCarPosition(car.index, position, carLook, up)
                 if physics.setCarVelocity then
                     physics.setCarVelocity(car.index, vec3(0,0,0))
                 end
                 ac.log("TELEPORT DEBUG: Teleport command sent for car " .. car.index)
                 ui.toast(ui.Icons.Confirm, "Teleported to " .. nodeName)
                 
                 -- Trigger Countdown
                 if battleActive then
                     countdownActive = true
                     countdownTimer = 3.0 -- 3 seconds countdown
                     
                     -- Store Freeze Position
                     countdownFreezePos = position
                     countdownFreezeLook = carLook
                     countdownFreezeUp = up
                     
                     ac.log("Countdown Started (Freeze Location Set)")
                 end
             else
                 ac.log("TELEPORT DEBUG: Teleport failed: physics.setCarPosition missing")
                 ac.sendChatMessage("/chasereport ERROR_NO_PHYSICS_API")
             end
        else
             ac.log("TELEPORT DEBUG: Teleport failed: Matrix missing")
             ac.sendChatMessage("/chasereport ERROR_NO_MATRIX")
        end
    else
        local msg = "Spawn point " .. nodeName .. " and AC_START_0 missing! Track might not support race mode."
        ac.log(msg)
        ac.sendChatMessage("/chasereport ERROR_NO_SPAWN") 
        ui.toast(ui.Icons.Warning, msg)
    end
end


-- Teleport Logic (Client-Side Fallback)
function script.onConsoleCommand(command, args)
    if command == "teleport_start" then
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
