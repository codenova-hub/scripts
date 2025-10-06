local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local RunService = game:GetService("RunService")
local CoreGui = game:GetService("CoreGui")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local player = Players.LocalPlayer
local Net = require(ReplicatedStorage:WaitForChild("Packages"):WaitForChild("Net"))

local TARGET_LABEL_NAME = "Generation"
local FLY_SPEED = 100
local BYPASS_COOLDOWN = 3.1
local ARRIVAL_DISTANCE = 5
local DECORATION_STOP_DISTANCE = 3
local DEcorATIONS_FOLDER_NAME = "Decorations"
local RESTART_DELAY = 2.0
local SAFE_FLIGHT_ALTITUDE = 40
local TOGGLE_KEY = Enum.KeyCode.G

local isRunning = false
local flightConnection = nil
local flightLV, flightAtt = nil, nil
local lastBypassTime = 0
local isEnabled = false

local goToBrainrot
local updateUI

local function printMsg(message)
    print("[GoToBrainrot] " .. tostring(message))
end

local function parseNum(text)
    text = tostring(text or "")
    local token = text:match("([%d%.]+%s*[KkMmBbTtQq]?)") or "0"
    token = token:gsub("%s","")
    local num, suf = token:match("([%d%.]+)([KkMmBbTtQq]?)")
    num = tonumber(num) or 0
    local mult = ({K=1e3, M=1e6, B=1e9, T=1e12, Q=1e15})[suf and suf:upper() or ""] or 1
    return num * mult
end

local function findBasePart(model)
    if model:FindFirstChild("Base") and model.Base:IsA("BasePart") then return model.Base end
    for _,v in ipairs(model:GetChildren()) do if v:IsA("BasePart") then return v end end
    return nil
end

local function stopFlight(reason, shouldRestart)
    if not isRunning then return end
    
    if flightConnection then
        flightConnection:Disconnect()
        flightConnection = nil
    end
    
    if flightLV then flightLV:Destroy() end
    if flightAtt then flightAtt:Destroy() end
    flightLV, flightAtt = nil, nil
    
    local char = player.Character
    local rootPart = char and char:FindFirstChild("HumanoidRootPart")
    if rootPart then
        rootPart.AssemblyLinearVelocity = Vector3.new(0,0,0)
    end

    isRunning = false
    if reason ~= "Chegou ao destino." then
        printMsg("Voo interrompido: " .. (reason or "N/A"))
    end

    if shouldRestart == nil then shouldRestart = true end

    if shouldRestart and isEnabled then
        task.delay(RESTART_DELAY, function()
            if not isRunning and isEnabled then
                goToBrainrot()
            end
        end)
    end
end

goToBrainrot = function()
    if isRunning or not isEnabled then return end

    if not player.Character or not player.Character:FindFirstChild("HumanoidRootPart") then
        printMsg("Aguardando o personagem carregar...")
        task.wait(1)
        if isEnabled then
            goToBrainrot()
        end
        return
    end

    local bestPet = {model = nil, value = -1}
    for _, label in ipairs(Workspace:GetDescendants()) do
        if label:IsA("TextLabel") and label.Name == TARGET_LABEL_NAME then
            local model = label:FindFirstAncestorOfClass("Model")
            if model and not tostring(model):lower():find("board") then
                local value = parseNum(label.Text)
                if value > bestPet.value then
                    bestPet = {model = model, value = value}
                end
            end
        end
    end

    if not bestPet.model then
        printMsg("Nenhum brainrot encontrado.")
        task.delay(RESTART_DELAY, goToBrainrot)
        return
    end
    
    local targetPart = findBasePart(bestPet.model)
    if not targetPart then
        printMsg("Não foi possível encontrar a parte base do melhor brainrot.")
        task.delay(RESTART_DELAY, goToBrainrot)
        return
    end

    local currentArrivalDistance = ARRIVAL_DISTANCE
    if targetPart.Position.Y < 10 then
        currentArrivalDistance = 3
    end

    local char = player.Character
    local rootPart = char and char:FindFirstChild("HumanoidRootPart")
    if not rootPart then
        printMsg("Personagem não encontrado.")
        task.delay(RESTART_DELAY, goToBrainrot)
        return
    end

    local humanoid = char:FindFirstChildOfClass("Humanoid")
    if not humanoid then
        printMsg("Humanoid não encontrado.")
        task.delay(RESTART_DELAY, goToBrainrot)
        return
    end
    local tool = char:FindFirstChildOfClass("Tool")
    if not (tool and tool.Name == "Grapple Hook") then
        local hook = player.Backpack:FindFirstChild("Grapple Hook")
        if hook then
            humanoid:EquipTool(hook)
            task.wait(0.2)
        else
            printMsg("Ferramenta 'Grapple Hook' não encontrada na mochila.")
            task.delay(RESTART_DELAY, goToBrainrot)
            return
        end
    end

    isRunning = true

    flightAtt = Instance.new("Attachment", rootPart)
    flightLV = Instance.new("LinearVelocity", rootPart)
    flightLV.Attachment0 = flightAtt
    flightLV.MaxForce = 100000
    flightLV.RelativeTo = Enum.ActuatorRelativeTo.World

    local directionToTarget = (targetPart.Position - rootPart.Position).Unit
    local sideOffset = Vector3.new(directionToTarget.Z, 0, -directionToTarget.X).Unit * 10
    local finalTargetPos = targetPart.Position + sideOffset

    local upwardTargetPos = rootPart.Position + Vector3.new(0, SAFE_FLIGHT_ALTITUDE, 0)
    local phase = "up"
    
    local decorationsFolder = Workspace:FindFirstChild(DEcorATIONS_FOLDER_NAME, true)
    local overlapParams = nil
    if decorationsFolder then
        overlapParams = OverlapParams.new()
        overlapParams.FilterType = Enum.RaycastFilterType.Include
        overlapParams.FilterDescendantsInstances = {decorationsFolder}
    end

    flightConnection = RunService.Heartbeat:Connect(function()
        if not isRunning or not player.Character or not bestPet.model or not bestPet.model.Parent then
            stopFlight("Alvo ou personagem inválido.")
            return
        end
        
        local currentRootPart = player.Character:FindFirstChild("HumanoidRootPart")
        if not currentRootPart then
            stopFlight("RootPart do personagem sumiu.")
            return
        end

        local currentTool = player.Character:FindFirstChildOfClass("Tool")
        if not (currentTool and currentTool.Name == "Grapple Hook") then
            local hook = player.Backpack:FindFirstChild("Grapple Hook")
            if hook then player.Character.Humanoid:EquipTool(hook) end
        end

        if overlapParams then
            local detectionSize = Vector3.new(DECORATION_STOP_DISTANCE, DECORATION_STOP_DISTANCE, DECORATION_STOP_DISTANCE)
            local partsInBox = Workspace:GetPartBoundsInBox(currentRootPart.CFrame, detectionSize, overlapParams)
            if #partsInBox > 0 then
                stopFlight("Proximidade com decoração detectada.")
                return
            end
        end

        if os.clock() - lastBypassTime > BYPASS_COOLDOWN then
            Net:RemoteEvent("UseItem"):FireServer(90 / 120)
            lastBypassTime = os.clock()
        end

        if phase == "up" then
            local distToUpwardTarget = (currentRootPart.Position - upwardTargetPos).Magnitude
            if distToUpwardTarget < currentArrivalDistance then
                phase = "to_target"
            else
                flightLV.VectorVelocity = (upwardTargetPos - currentRootPart.Position).Unit * FLY_SPEED
            end
        elseif phase == "to_target" then
            local currentTargetPos = bestPet.model and findBasePart(bestPet.model)
            if not currentTargetPos then
                stopFlight("Alvo desapareceu.")
                return
            end
            
            local updatedFinalTargetPos = currentTargetPos.Position + sideOffset
            local distToTarget = (currentRootPart.Position - updatedFinalTargetPos).Magnitude
            if distToTarget < currentArrivalDistance then
                stopFlight("Chegou ao destino.")
                return
            else
                flightLV.VectorVelocity = (updatedFinalTargetPos - currentRootPart.Position).Unit * FLY_SPEED
            end
        end
    end)
end

local toggleUI

local function createToggleUI()
    local screenGui = Instance.new("ScreenGui")
    screenGui.Name = "BrainrotToggleUI"
    screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    screenGui.ResetOnSpawn = false

    local mainFrame = Instance.new("TextButton")
    mainFrame.Name = "MainFrame"
    mainFrame.Size = UDim2.new(0, 150, 0, 40)
    mainFrame.Position = UDim2.new(0.5, -75, 0, 20)
    mainFrame.BackgroundColor3 = Color3.fromRGB(35, 35, 35)
    mainFrame.BorderColor3 = Color3.fromRGB(20, 20, 20)
    mainFrame.BorderSizePixel = 2
    mainFrame.AutoButtonColor = false
    mainFrame.Text = ""

    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, 8)
    corner.Parent = mainFrame

    local statusLabel = Instance.new("TextLabel")
    statusLabel.Name = "StatusLabel"
    statusLabel.Size = UDim2.new(1, 0, 1, 0)
    statusLabel.BackgroundColor3 = Color3.fromRGB(255, 80, 80)
    statusLabel.BackgroundTransparency = 0.2
    statusLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
    statusLabel.Font = Enum.Font.SourceSansBold
    statusLabel.TextSize = 18
    statusLabel.Text = "INATIVO"
    statusLabel.Parent = mainFrame
    
    local cornerLabel = Instance.new("UICorner")
    cornerLabel.CornerRadius = UDim.new(0, 8)
    cornerLabel.Parent = statusLabel

    mainFrame.Parent = screenGui
    screenGui.Parent = CoreGui

    toggleUI = {
        gui = screenGui,
        statusLabel = statusLabel
    }

    mainFrame.MouseButton1Click:Connect(function()
        toggleScript()
    end)
end

updateUI = function()
    if not toggleUI then return end
    if isEnabled then
        toggleUI.statusLabel.Text = "ATIVO"
        toggleUI.statusLabel.BackgroundColor3 = Color3.fromRGB(80, 255, 80)
    else
        toggleUI.statusLabel.Text = "CLIQUE PARA ATIVAR"
        toggleUI.statusLabel.BackgroundColor3 = Color3.fromRGB(255, 80, 80)
    end
end

function toggleScript()
    isEnabled = not isEnabled
    printMsg("Script " .. (isEnabled and "ATIVADO" or "DESATIVADO") .. " pelo usuário.")
    updateUI()

    if isEnabled then
        goToBrainrot()
    else
        if isRunning then
            stopFlight("Desativado pelo usuário.", false)
        end
    end
end

UserInputService.InputBegan:Connect(function(input, gameProcessed)
    if gameProcessed then return end
    endinput.KeyCode == TOGGLE_KEY then
end)    toggleScript()
    end
createToggleUI()
updateUI()
printMsg("Script carregado. Pressione G ou clique na UI para ativar.")
