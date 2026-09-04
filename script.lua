-- ==========================================
-- COMPLETE FEATURES - No Key System
-- ==========================================

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local VirtualInputManager = game:GetService("VirtualInputManager")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local player = Players.LocalPlayer
local camera = Workspace.CurrentCamera

print("Features loaded!")

-- ==========================================
-- AUTO PARRY
-- ==========================================
local function calculateBallRadius(speed)
    local minR = 15
    local maxR = 90
    local sFactor = math.clamp(speed / 300, 0, 1)
    return minR + (maxR - minR) * (sFactor * sFactor * 0.7)
end

local ballStates = {}
local lastParryClock = 0
local pendingQueue = {}
local isProcessing = false

local function executeParry()
    local now = os.clock()
    local jitter = math.random(10, 45) / 1000
    if now - lastParryClock < (0.09 + jitter) then return false end
    lastParryClock = now
    pcall(function()
        VirtualInputManager:SendKeyEvent(true, Enum.KeyCode.F, false, game)
        task.wait(0.001)
        VirtualInputManager:SendKeyEvent(false, Enum.KeyCode.F, false, game)
    end)
    return true
end

local function processQueue()
    if isProcessing then return end
    isProcessing = true
    task.spawn(function()
        while #pendingQueue > 0 do
            table.remove(pendingQueue, 1)
            executeParry()
            if #pendingQueue > 0 then
                task.wait(0.002)
            end
        end
        isProcessing = false
    end)
end

local function queueParry()
    if #pendingQueue >= 10 then return end
    table.insert(pendingQueue, #pendingQueue + 1)
    processQueue()
end

-- ==========================================
-- ESP SYSTEM
-- ==========================================
local espGui = Instance.new("ScreenGui")
espGui.Name = "Overlay"
espGui.ResetOnSpawn = false
espGui.IgnoreGuiInset = true
espGui.Parent = player:WaitForChild("PlayerGui")

local espContainers = {}

local function setupPlayerEsp(plr)
    if plr == player then return end
    local container = Instance.new("Folder")
    container.Name = "PlayerESP"
    container.Parent = espGui
    
    local box = Instance.new("Frame")
    box.BackgroundTransparency = 1
    box.Visible = false
    box.Parent = container
    local stroke = Instance.new("UIStroke")
    stroke.Color = Color3.fromRGB(0, 200, 150)
    stroke.Thickness = 1
    stroke.Parent = box
    
    local nameLabel = Instance.new("TextLabel")
    nameLabel.BackgroundTransparency = 1
    nameLabel.Size = UDim2.new(0, 200, 0, 15)
    nameLabel.AnchorPoint = Vector2.new(0.5, 1)
    nameLabel.TextColor3 = Color3.fromRGB(220, 220, 230)
    nameLabel.TextSize = 13
    nameLabel.Font = Enum.Font.GothamBold
    nameLabel.TextStrokeTransparency = 0.5
    nameLabel.Visible = false
    nameLabel.Parent = container
    
    espContainers[plr] = {Box = box, Name = nameLabel}
end

for _, p in ipairs(Players:GetPlayers()) do setupPlayerEsp(p) end
Players.PlayerAdded:Connect(setupPlayerEsp)
Players.PlayerRemoving:Connect(function(p)
    if espContainers[p] then
        if espContainers[p].Box and espContainers[p].Box.Parent then
            espContainers[p].Box.Parent:Destroy()
        end
        espContainers[p] = nil
    end
end)

-- ==========================================
-- MAIN LOOP
-- ==========================================
local frameCounter = 0

RunService.Heartbeat:Connect(function(heartbeatDt)
    frameCounter = frameCounter + 1
    if frameCounter % math.random(12, 50) == 0 then return end
    
    local character = player.Character
    if not character or not character:FindFirstChild("HumanoidRootPart") then
        return
    end
    
    local hrp = character.HumanoidRootPart
    local hrpPos = hrp.Position
    local dt = math.max(heartbeatDt, 1/240)
    
    -- ESP UPDATE
    if frameCounter % 2 == 0 then
        pcall(function()
            for p, visuals in pairs(espContainers) do
                local pChar = p.Character
                local pRoot = pChar and pChar:FindFirstChild("HumanoidRootPart")
                local pHead = pChar and pChar:FindFirstChild("Head")
                if pRoot and pHead then
                    local headPos, headVis = camera:WorldToViewportPoint(pHead.Position + Vector3.new(0, 0.8, 0))
                    local footPos, footVis = camera:WorldToViewportPoint(pRoot.Position - Vector3.new(0, 3.1, 0))
                    if headVis or footVis then
                        local height = math.abs(footPos.Y - headPos.Y)
                        local width = height * 0.6
                        local posX = headPos.X - (width / 2)
                        local posY = headPos.Y
                        
                        if visuals.Box then
                            visuals.Box.Visible = true
                            visuals.Box.Position = UDim2.new(0, posX, 0, posY)
                            visuals.Box.Size = UDim2.new(0, width, 0, height)
                        end
                        
                        local textOffsetY = posY - 18
                        if visuals.Name then
                            visuals.Name.Visible = true
                            visuals.Name.Text = p.Name
                            visuals.Name.Position = UDim2.new(0, headPos.X, 0, textOffsetY)
                        end
                    else
                        if visuals.Box then visuals.Box.Visible = false end
                        if visuals.Name then visuals.Name.Visible = false end
                    end
                end
            end
        end)
    end
    
    -- AUTO PARRY
    local balls = Workspace:FindFirstChild("Balls")
    if balls then
        for _, ball in ipairs(balls:GetChildren()) do
            if ball:IsA("BasePart") then
                local currentPos = ball.Position
                local velocity = ball.AssemblyLinearVelocity
                local speed = velocity.Magnitude
                local currentRadius = calculateBallRadius(speed)
                local state = ballStates[ball]
                if not state then
                    state = {lastTarget = nil, parriedThisTarget = false, lastPosition = currentPos, lastVelocity = velocity, smoothedAccel = Vector3.zero}
                    ballStates[ball] = state
                end
                if not ball.Parent then
                    ballStates[ball] = nil
                    break
                end
                local distance3D = (hrpPos - currentPos).Magnitude
                if distance3D > (currentRadius + 140) then state.parriedThisTarget = false end
                local currentTarget = ball:GetAttribute("target")
                if currentTarget ~= state.lastTarget then
                    state.lastTarget = currentTarget
                    state.parriedThisTarget = false
                end
                local triggeredThisFrame = false
                if speed > 1 then
                    local toPlayer = hrpPos - currentPos
                    local vNorm = velocity.Unit
                    local projDist = toPlayer:Dot(vNorm)
                    if projDist >= 0 then
                        local closestPoint = currentPos + vNorm * projDist
                        local perpDist = (closestPoint - hrpPos).Magnitude
                        if perpDist <= currentRadius then
                            local approachDist = projDist - math.sqrt(math.max(0, (currentRadius * currentRadius) - (perpDist * perpDist)))
                            local predictedTime = approachDist / speed
                            if predictedTime <= 0.45 then
                                triggeredThisFrame = true
                            end
                        end
                    end
                end
                if not triggeredThisFrame and distance3D <= currentRadius then
                    triggeredThisFrame = true
                end
                if currentTarget == player.Name and not state.parriedThisTarget then
                    if triggeredThisFrame then
                        queueParry()
                        state.parriedThisTarget = true
                    end
                end
                state.lastPosition = currentPos
                state.lastVelocity = velocity
            end
        end
    end
end)

print("All features loaded successfully!")
