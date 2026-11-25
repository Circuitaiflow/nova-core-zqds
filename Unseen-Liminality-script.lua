local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TextChatService = game:GetService("TextChatService")
local LocalPlayer = Players.LocalPlayer

local GlobalCData = require(ReplicatedStorage.Modules.GlobalCData)

local CustomRates = {
    DrainRate = 0.4,
    RegenRate = 1.0,
}

local realStamina = GlobalCData.Stamina or 100
local lastStamina = realStamina

local staminaThread = task.spawn(function()
    while task.wait() do
        local current = GlobalCData.Stamina
        if current ~= lastStamina then
            local diff = current - lastStamina
            
            if diff < 0 then
                local lossRatio = diff / -0.4
                realStamina = math.clamp(realStamina - (CustomRates.DrainRate * lossRatio), 0, GlobalCData.MaxStamina or 100)
            elseif diff > 0 then
                local gainRatio = diff / 1.0
                realStamina = math.clamp(realStamina + (CustomRates.RegenRate * gainRatio), 0, GlobalCData.MaxStamina or 100)
            end
            
            GlobalCData.Stamina = realStamina
            lastStamina = realStamina
        end
    end
end)

local isNoclipping = false
local customWalkSpeed = 16
local customJumpPower = 50
local overrideWalkSpeed = false
local overrideJumpPower = false

local dynamicAnimEnabled = false
local baseWalkSpeed = 16

local whistleEnabled = false
local whistleDelay = 0.45
local whistleThread = nil

local ChatMimicConfig = {
    Enabled = false,
    TargetPlayer = nil,
    Mode = "Glitched",
    MimicChance = 100,
    MinDelay = 1,
    MaxDelay = 2,
    DistortionDelay = 45
}

local ChatHistoryBuffer = {}
local PanicPhrases = {
    "why is it looking at me",
    "dont turn around",
    "its right behind you",
    "do you hear that",
    "run",
    "stop looking at me"
}

local chatConnection = nil
local noclipConnection = nil
local movementConnection = nil
local animConnection = nil

local function getLocalCharacter()
    return LocalPlayer.Character or GlobalCData.Character
end

local function safeReverse(str)
    local chars = {}
    for _, code in utf8.codes(str) do
        table.insert(chars, 1, utf8.char(code))
    end
    return table.concat(chars)
end

function sendChatMessage(msg)
    pcall(function()
        if TextChatService.ChatVersion == Enum.ChatVersion.TextChatService then
            local textChannel = TextChatService.TextChannels:FindFirstChild("RBXGeneral")
            if textChannel then
                textChannel:SendAsync(msg)
            else
                for _, channel in ipairs(TextChatService.TextChannels:GetChildren()) do
                    if channel:IsA("TextChannel") then
                        channel:SendAsync(msg)
                        break
                    end
                end
            end
        else
            ReplicatedStorage.DefaultChatSystemChatEvents.SayMessageRequest:FireServer(msg, "All")
        end
    end)
end

local function alterText(text)
    if math.random(1, 100) > ChatMimicConfig.MimicChance then return nil end

    if ChatMimicConfig.Mode == "Glitched" then
        local suffixes = {"...", "..?", "...", " _ "}
        return text:sub(1, math.max(1, #text - 2)) .. suffixes[math.random(1, #suffixes)]
        
    elseif ChatMimicConfig.Mode == "Reverse" then
        return safeReverse(text)
        
    elseif ChatMimicConfig.Mode == "Whisper" then
        return "... " .. text:lower() .. " ..."
        
    elseif ChatMimicConfig.Mode == "Delayed" then
        table.insert(ChatHistoryBuffer, text)
        task.delay(ChatMimicConfig.DistortionDelay, function()
            if #ChatHistoryBuffer > 0 then
                local pastMsg = table.remove(ChatHistoryBuffer, 1)
                sendChatMessage("... " .. pastMsg .. " ...")
            end
        end)
        return nil
        
    elseif ChatMimicConfig.Mode == "Fake Panic" then
        return PanicPhrases[math.random(1, #PanicPhrases)]
    end
    
    return text
end

local function setCharacterCollisions(enabled)
    local char = getLocalCharacter()
    if char then
        for _, obj in ipairs(char:GetDescendants()) do
            if obj:IsA("BasePart") then
                if enabled then
                    if obj.Name == "HumanoidRootPart" then
                        obj.CanCollide = false
                    elseif obj:IsA("MeshPart") or obj.Name == "Head" or obj.Name == "Torso" or string.find(obj.Name, "Leg") or string.find(obj.Name, "Arm") then
                        obj.CanCollide = true
                    elseif obj.Parent:IsA("Accessory") or obj.Parent:IsA("Hat") then
                        obj.CanCollide = false
                    end
                else
                    obj.CanCollide = false
                end
            end
        end
    end
end

noclipConnection = RunService.Stepped:Connect(function()
    if isNoclipping then
        setCharacterCollisions(false)
    end
end)

movementConnection = RunService.RenderStepped:Connect(function()
    local char = getLocalCharacter()
    if char then
        local hum = char:FindFirstChildOfClass("Humanoid")
        if hum then
            if overrideWalkSpeed then
                hum.WalkSpeed = customWalkSpeed
            end
            if overrideJumpPower then
                hum.UseJumpPower = true
                hum.JumpPower = customJumpPower
            end
        end
    end
end)

animConnection = RunService.Stepped:Connect(function()
    if dynamicAnimEnabled then
        local char = getLocalCharacter()
        if char then
            local hum = char:FindFirstChildOfClass("Humanoid")
            local hrp = char:FindFirstChild("HumanoidRootPart")
            if hum and hrp then
                local currentVelocity = (hrp.AssemblyLinearVelocity * Vector3.new(1, 0, 1)).Magnitude
                local calculatedSpeed = currentVelocity / baseWalkSpeed
                if currentVelocity < 0.1 then
                    calculatedSpeed = 1.0
                end
                
                local animator = hum:FindFirstChildOfClass("Animator")
                if animator then
                    for _, track in ipairs(animator:GetPlayingAnimationTracks()) do
                        track:AdjustSpeed(calculatedSpeed)
                    end
                end
            end
        end
    end
end)

local function triggerWhistle()
    pcall(function()
        local events = ReplicatedStorage:FindFirstChild("Events")
        if events then
            local gameMisc = events:FindFirstChild("GameMisc")
            if gameMisc then
                gameMisc:FireServer({[1] = "Whistle"})
            end
        end
    end)
end

local function stopWhistleThread()
    if whistleThread then
        task.cancel(whistleThread)
        whistleThread = nil
    end
end

local function startWhistleThread()
    stopWhistleThread()
    whistleThread = task.spawn(function()
        while whistleEnabled do
            triggerWhistle()
            task.wait(math.max(whistleDelay, 0.45))
        end
    end)
end

local function setupChatMimic()
    if chatConnection then chatConnection:Disconnect() end

    local function processIncoming(player, text)
        if not ChatMimicConfig.Enabled or not ChatMimicConfig.TargetPlayer then return end
        if player == ChatMimicConfig.TargetPlayer then
            local modified = alterText(text)
            if modified then
                task.wait(math.random(ChatMimicConfig.MinDelay, ChatMimicConfig.MaxDelay))
                sendChatMessage(modified)
            end
        end
    end

    pcall(function()
        if TextChatService.ChatVersion == Enum.ChatVersion.TextChatService then
            chatConnection = TextChatService.MessageReceived:Connect(function(message)
                if message.TextSource then
                    local player = Players:GetPlayerByUserId(message.TextSource.UserId)
                    processIncoming(player, message.Text)
                end
            end)
        end
    end)

    if not chatConnection then
        chatConnection = Players.PlayerChatted:Connect(function(type, plr, msg)
            processIncoming(plr, msg)
        end)
    end
end

local Rayfield = loadstring(game:HttpGet('https://sirius.menu/rayfield'))()

local Window = Rayfield:CreateWindow({
    Name = "Unseen Liminality",
    LoadingTitle = "By M00KIE",
    LoadingSubtitle = "😹✌️",
    ConfigurationSaving = { Enabled = false },
    KeySystem = false
})

local MainTab = Window:CreateTab("Stamina Controls", 4483362458)

MainTab:CreateSection("Stamina Rates (Per Second)")

local DrainSlider = MainTab:CreateSlider({
    Name = "Stamina Loss Rate",
    Range = {0, 50},
    Increment = 0.5,
    Suffix = " /sec",
    CurrentValue = CustomRates.DrainRate * 10,
    Flag = "StaminaLoss",
    Callback = function(Value)
        CustomRates.DrainRate = Value / 10
    end,
})

local GainSlider = MainTab:CreateSlider({
    Name = "Stamina Gain Rate",
    Range = {0, 50},
    Increment = 0.5,
    Suffix = " /sec",
    CurrentValue = CustomRates.RegenRate * 10,
    Flag = "StaminaGain",
    Callback = function(Value)
        CustomRates.RegenRate = Value / 10
    end,
})

MainTab:CreateSection("Quick Actions")

MainTab:CreateButton({
    Name = "Infinite Sprint (0 Loss)",
    Callback = function()
        DrainSlider:Set(0)
        Rayfield:Notify({ Title = "Stamina", Content = "Infinite Sprint Enabled!", Duration = 2 })
    end,
})

MainTab:CreateButton({
    Name = "Reset Defaults (4 Loss / 10 Gain)",
    Callback = function()
        DrainSlider:Set(4)
        GainSlider:Set(10)
        Rayfield:Notify({ Title = "Stamina", Content = "Reset to standard values.", Duration = 2 })
    end,
})

local VisualsTab = Window:CreateTab("Visuals", 4483362458)

local eventConnections = {}

local npcHighlightsEnabled = false
local playerHighlightsEnabled = false

local npcFillColor = Color3.fromRGB(255, 50, 50)
local npcOutlineColor = Color3.fromRGB(255, 255, 255)

local playerFillColor = Color3.fromRGB(0, 200, 255)
local playerOutlineColor = Color3.fromRGB(255, 255, 255)

local function getHighlightColor(model, isPlayer)
    if isPlayer then
        return playerFillColor, playerOutlineColor
    else
        return npcFillColor, npcOutlineColor
    end
end

local function updateModelHighlight(model, isPlayer)
    if not model or model == getLocalCharacter() then return end
    
    local hum = model:FindFirstChildOfClass("Humanoid")
    if not hum then return end

    local shouldHighlight = (isPlayer and playerHighlightsEnabled) or (not isPlayer and npcHighlightsEnabled)
    local highlight = model:FindFirstChild("PersistentHighlight")

    if shouldHighlight then
        local fillColor, outlineColor = getHighlightColor(model, isPlayer)
        if not highlight then
            highlight = Instance.new("Highlight")
            highlight.Name = "PersistentHighlight"
            highlight.Adornee = model
            highlight.FillTransparency = 0.5
            highlight.OutlineTransparency = 0
            highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
            highlight.Parent = model
        end
        highlight.FillColor = fillColor
        highlight.OutlineColor = outlineColor
    else
        if highlight then
            highlight:Destroy()
        end
    end
end

local function applyHighlights()
    for _, obj in ipairs(workspace:GetDescendants()) do
        if obj:IsA("Model") and obj:FindFirstChildOfClass("Humanoid") then
            local isPlayer = Players:GetPlayerFromCharacter(obj) ~= nil
            updateModelHighlight(obj, isPlayer)
        end
    end
end

local function setupAutoHighlighting()
    for _, conn in ipairs(eventConnections) do
        if typeof(conn) == "RBXScriptConnection" then
            conn:Disconnect()
        end
    end
    eventConnections = {}

    local function trackModel(model)
        local humCheck = model:FindFirstChildOfClass("Humanoid")
        if humCheck then
            local isPlayer = Players:GetPlayerFromCharacter(model) ~= nil
            updateModelHighlight(model, isPlayer)
            
            local parentConn
            parentConn = model.AncestryChanged:Connect(function(_, parent)
                if not parent then
                    if parentConn then parentConn:Disconnect() end
                end
            end)
            table.insert(eventConnections, parentConn)
        end
    end

    local wsChildConn = workspace.DescendantAdded:Connect(function(obj)
        if obj:IsA("Model") then
            task.delay(0.3, function()
                if obj and obj.Parent then
                    trackModel(obj)
                end
            end)
        end
    end)
    table.insert(eventConnections, wsChildConn)

    for _, obj in ipairs(workspace:GetDescendants()) do
        if obj:IsA("Model") then
            trackModel(obj)
        end
    end
end

setupAutoHighlighting()

VisualsTab:CreateSection("Toggles")

VisualsTab:CreateToggle({
    Name = "Highlight NPCs",
    CurrentValue = false,
    Flag = "NPCHighlightToggle",
    Callback = function(Value)
        npcHighlightsEnabled = Value
        applyHighlights()
    end,
})

VisualsTab:CreateToggle({
    Name = "Highlight Players",
    CurrentValue = false,
    Flag = "PlayerHighlightToggle",
    Callback = function(Value)
        playerHighlightsEnabled = Value
        applyHighlights()
    end,
})

VisualsTab:CreateSection("NPC Colors")

VisualsTab:CreateColorPicker({
    Name = "NPC Fill Color",
    Color = npcFillColor,
    Flag = "NPCFillColorPicker",
    Callback = function(Value)
        npcFillColor = Value
        applyHighlights()
    end,
})

VisualsTab:CreateColorPicker({
    Name = "NPC Outline Color",
    Color = npcOutlineColor,
    Flag = "NPCOutlineColorPicker",
    Callback = function(Value)
        npcOutlineColor = Value
        applyHighlights()
    end,
})

VisualsTab:CreateSection("Player Colors")

VisualsTab:CreateColorPicker({
    Name = "Player Fill Color",
    Color = playerFillColor,
    Flag = "PlayerFillColorPicker",
    Callback = function(Value)
        playerFillColor = Value
        applyHighlights()
    end,
})

VisualsTab:CreateColorPicker({
    Name = "Player Outline Color",
    Color = playerOutlineColor,
    Flag = "PlayerOutlineColorPicker",
    Callback = function(Value)
        playerOutlineColor = Value
        applyHighlights()
    end,
})

VisualsTab:CreateSection("Controls")

VisualsTab:CreateButton({
    Name = "Refresh Highlights",
    Callback = function()
        applyHighlights()
        Rayfield:Notify({ Title = "Visuals", Content = "Refreshed highlights.", Duration = 2 })
    end,
})

local UtilityTab = Window:CreateTab("Player & Utility", 4483362458)

UtilityTab:CreateSection("Movement Controls")

UtilityTab:CreateToggle({
    Name = "Noclip",
    CurrentValue = false,
    Flag = "NoclipToggle",
    Callback = function(Value)
        isNoclipping = Value
        if not Value then
            setCharacterCollisions(true)
        end
        Rayfield:Notify({ Title = "Noclip", Content = isNoclipping and "Enabled" or "Disabled", Duration = 2 })
    end,
})

local WalkSpeedSlider = UtilityTab:CreateSlider({
    Name = "WalkSpeed",
    Range = {16, 250},
    Increment = 1,
    Suffix = " spd",
    CurrentValue = 16,
    Flag = "WalkSpeedSlider",
    Callback = function(Value)
        customWalkSpeed = Value
        overrideWalkSpeed = (Value ~= 16)
        
        local char = getLocalCharacter()
        if char then
            local hum = char:FindFirstChildOfClass("Humanoid")
            if hum then
                hum.WalkSpeed = Value
            end
        end
    end,
})

local JumpPowerSlider = UtilityTab:CreateSlider({
    Name = "JumpPower",
    Range = {50, 300},
    Increment = 5,
    Suffix = " pwr",
    CurrentValue = 50,
    Flag = "JumpPowerSlider",
    Callback = function(Value)
        customJumpPower = Value
        overrideJumpPower = (Value ~= 50)
        
        local char = getLocalCharacter()
        if char then
            local hum = char:FindFirstChildOfClass("Humanoid")
            if hum then
                hum.UseJumpPower = true
                hum.JumpPower = Value
            end
        end
    end,
})

UtilityTab:CreateButton({
    Name = "Reset Movement Defaults",
    Callback = function()
        WalkSpeedSlider:Set(16)
        JumpPowerSlider:Set(50)
        overrideWalkSpeed = false
        overrideJumpPower = false
        Rayfield:Notify({ Title = "Movement", Content = "Speed & Jump reset to default.", Duration = 2 })
    end,
})

UtilityTab:CreateSection("Animation Controls")

UtilityTab:CreateToggle({
    Name = "Dynamic Animation Scaling",
    CurrentValue = false,
    Flag = "DynamicAnimToggle",
    Callback = function(Value)
        dynamicAnimEnabled = Value
        if not Value then
            local char = getLocalCharacter()
            if char then
                local hum = char:FindFirstChildOfClass("Humanoid")
                if hum then
                    local animator = hum:FindFirstChildOfClass("Animator")
                    if animator then
                        for _, track in ipairs(animator:GetPlayingAnimationTracks()) do
                            track:AdjustSpeed(1.0)
                        end
                    end
                end
            end
        end
        Rayfield:Notify({ Title = "Animations", Content = Value and "Dynamic Scaling Enabled" or "Reset to Normal", Duration = 2 })
    end,
})

UtilityTab:CreateSection("Whistle Loop")

UtilityTab:CreateToggle({
    Name = "Auto Whistle",
    CurrentValue = false,
    Flag = "WhistleToggle",
    Callback = function(Value)
        whistleEnabled = Value
        if Value then
            startWhistleThread()
        else
            stopWhistleThread()
        end
        Rayfield:Notify({ Title = "Whistle", Content = Value and "Whistle loop started" or "Whistle loop stopped", Duration = 2 })
    end,
})

UtilityTab:CreateSlider({
    Name = "Whistle Delay",
    Range = {0.45, 5.0},
    Increment = 0.05,
    Suffix = "s",
    CurrentValue = 0.45,
    Flag = "WhistleDelaySlider",
    Callback = function(Value)
        whistleDelay = math.max(Value, 0.45)
    end,
})

UtilityTab:CreateSection("Teleportation")

local targetPlayerTP = nil
local playerTPMap = {}
local playerTPNames = {}
local playerTPDropdown = nil

local function updatePlayerTPList()
    playerTPMap = {}
    playerTPNames = {}
    for _, plr in ipairs(Players:GetPlayers()) do
        if plr ~= LocalPlayer then
            local name = plr.DisplayName .. " (@" .. plr.Name .. ")"
            table.insert(playerTPNames, name)
            playerTPMap[name] = plr
        end
    end
    if #playerTPNames == 0 then
        table.insert(playerTPNames, "No Players Found")
    end
    if playerTPDropdown then
        playerTPDropdown:Refresh(playerTPNames)
        targetPlayerTP = playerTPMap[playerTPNames[1]]
    end
end

updatePlayerTPList()

playerTPDropdown = UtilityTab:CreateDropdown({
    Name = "Select Player to Teleport",
    Options = playerTPNames,
    CurrentOption = playerTPNames[1] or "No Players Found",
    Flag = "PlayerTPDropdown",
    Callback = function(Option)
        if type(Option) == "table" then Option = Option[1] end
        targetPlayerTP = playerTPMap[Option]
    end,
})

local robustPlayerAddConn = Players.PlayerAdded:Connect(function()
    task.wait(0.2)
    updatePlayerTPList()
end)
table.insert(eventConnections, robustPlayerAddConn)

local robustPlayerRemConn = Players.PlayerRemoving:Connect(function()
    task.wait(0.1)
    updatePlayerTPList()
end)
table.insert(eventConnections, robustPlayerRemConn)

UtilityTab:CreateButton({
    Name = "Refresh Player List",
    Callback = function()
        updatePlayerTPList()
        Rayfield:Notify({ Title = "Player List", Content = "Refreshed active players.", Duration = 2 })
    end,
})

UtilityTab:CreateButton({
    Name = "Teleport to Player",
    Callback = function()
        if targetPlayerTP and targetPlayerTP.Character then
            local targetHRP = targetPlayerTP.Character:FindFirstChild("HumanoidRootPart")
            local myChar = getLocalCharacter()
            if myChar and targetHRP then
                local myHRP = myChar:FindFirstChild("HumanoidRootPart")
                if myHRP then
                    local targetPos = targetHRP.Position + Vector3.new(0, 3, 3)
                    task.spawn(function()
                        pcall(function()
                            LocalPlayer:RequestStreamAroundAsync(targetPos)
                        end)
                        task.wait(0.1)
                        myChar:PivotTo(CFrame.new(targetPos))
                        Rayfield:Notify({ Title = "Teleported", Content = "Arrived at " .. targetPlayerTP.Name, Duration = 2 })
                    end)
                end
            end
        end
    end,
})

local MimicTab = Window:CreateTab("Chat Mimic", 4483362458)

MimicTab:CreateSection("Target & Mode Selection")

MimicTab:CreateDropdown({
    Name = "Target Player",
    Options = playerTPNames,
    CurrentOption = playerTPNames[1] or "No Players Found",
    Flag = "MimicTargetDropdown",
    Callback = function(Option)
        if type(Option) == "table" then Option = Option[1] end
        ChatMimicConfig.TargetPlayer = playerTPMap[Option]
    end,
})

MimicTab:CreateDropdown({
    Name = "Mimic Mode",
    Options = {"Glitched", "Reverse", "Whisper", "Delayed", "Fake Panic"},
    CurrentOption = "Glitched",
    Flag = "MimicModeDropdown",
    Callback = function(Option)
        if type(Option) == "table" then Option = Option[1] end
        ChatMimicConfig.Mode = Option
    end,
})

MimicTab:CreateToggle({
    Name = "Enable Chat Mimic",
    CurrentValue = false,
    Flag = "MimicToggle",
    Callback = function(Value)
        ChatMimicConfig.Enabled = Value
        if Value then
            setupChatMimic()
            Rayfield:Notify({ Title = "Chat Mimic", Content = "Mimic Active.", Duration = 2 })
        else
            if chatConnection then chatConnection:Disconnect() end
            Rayfield:Notify({ Title = "Chat mimic", Content = "Mimic Disabled.", Duration = 2 })
        end
    end,
})

MimicTab:CreateSection("Fine-Tuning Settings")

MimicTab:CreateSlider({
    Name = "Mimic Trigger Chance",
    Range = {10, 100},
    Increment = 5,
    Suffix = "%",
    CurrentValue = 100,
    Flag = "MimicChanceSlider",
    Callback = function(Value)
        ChatMimicConfig.MimicChance = Value
    end,
})

MimicTab:CreateSlider({
    Name = "Distortion Delay (Delayed Mode)",
    Range = {15, 120},
    Increment = 5,
    Suffix = "s",
    CurrentValue = 45,
    Flag = "MimicDistortionSlider",
    Callback = function(Value)
        ChatMimicConfig.DistortionDelay = Value
    end,
})

local InfoTab = Window:CreateTab("Info", 4483362458)

InfoTab:CreateSection("Feature Guide")

InfoTab:CreateParagraph({Title = "Stamina Controls", Content = "Adjusts your sprint drain and gain rates in real-time, or gives you infinite sprint."})
InfoTab:CreateParagraph({Title = "Visuals (ESP)", Content = "Highlights players and NPCs through walls with customizable colors and outline modes."})
InfoTab:CreateParagraph({Title = "Player & Utility", Content = "Includes Noclip, custom WalkSpeed/JumpPower, smooth animation speed scaling, an auto-whistle loop, and player teleports."})
InfoTab:CreateParagraph({Title = "Chat Mimic", Content = "Monitors a target player's chat and repeats their messages with creepy distortions like reverse text or fake panic."})

local SettingsTab = Window:CreateTab("Settings", 4483362458)

SettingsTab:CreateSection("GUI Management")

SettingsTab:CreateButton({
    Name = "Unload GUI",
    Callback = function()
        whistleEnabled = false
        stopWhistleThread()
        
        ChatMimicConfig.Enabled = false
        if chatConnection then chatConnection:Disconnect() end
        
        if staminaThread then task.cancel(staminaThread) end
        if noclipConnection then noclipConnection:Disconnect() end
        if movementConnection then movementConnection:Disconnect() end
        if animConnection then animConnection:Disconnect() end
        
        for _, conn in ipairs(eventConnections) do
            if typeof(conn) == "RBXScriptConnection" then
                conn:Disconnect()
            end
        end
        eventConnections = {}
        
        for _, obj in ipairs(workspace:GetDescendants()) do
            if obj:IsA("Highlight") and obj.Name == "PersistentHighlight" then
                obj:Destroy()
            end
        end
        
        local char = getLocalCharacter()
        if char then
            local hum = char:FindFirstChildOfClass("Humanoid")
            if hum then
                local animator = hum:FindFirstChildOfClass("Animator")
                if animator then
                    for _, track in ipairs(animator:GetPlayingAnimationTracks()) do
                        track:AdjustSpeed(1.0)
                    end
                end
            end
        end
        
        setCharacterCollisions(true)
        Rayfield:Destroy()
    end,
})
