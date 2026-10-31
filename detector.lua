--!strict
--[[
    ========================================================================
    STEAL PANEL - DETECTOR AUTOMÁTICO DE HUEVOS REALES
    ========================================================================
    Escanea el Workspace en tiempo real para detectar los huevos reales 
    existentes en el mapa, mostrando sus nombres reales, distancia y opción de rastreo.
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local localPlayer = Players.LocalPlayer
local playerGui = localPlayer:WaitForChild("PlayerGui")

local THEME = {
    Bg = Color3.fromRGB(20, 22, 28),
    CardBg = Color3.fromRGB(30, 33, 42),
    Accent = Color3.fromRGB(255, 185, 45),
    Header = Color3.fromRGB(26, 28, 36),
    Text = Color3.fromRGB(245, 245, 245),
    Muted = Color3.fromRGB(150, 155, 170),
    Success = Color3.fromRGB(46, 204, 113),
}

------------------------------------------------------------------------
-- 1. LIMPIEZA PREVENTIVA
------------------------------------------------------------------------
local GUI_NAME = "StealPanel_AutoEggTracker"
local prevGui = playerGui:FindFirstChild(GUI_NAME)
if prevGui then
    prevGui:Destroy()
end

------------------------------------------------------------------------
-- 2. ESTADO DINÁMICO
------------------------------------------------------------------------
type RealEggEntry = {
    Card: Frame,
    DistLabel: TextLabel,
    TargetInstance: Instance,
    TargetPart: BasePart,
    Billboard: BillboardGui?,
    Highlight: Highlight?,
}

local detectedEggs: {[Instance]: RealEggEntry} = {}

------------------------------------------------------------------------
-- 3. CONSTRUCCIÓN DE LA INTERFAZ
------------------------------------------------------------------------
local screenGui = Instance.new("ScreenGui")
screenGui.Name = GUI_NAME
screenGui.ResetOnSpawn = false
screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

local mainFrame = Instance.new("Frame")
mainFrame.Name = "StealPanelFrame"
mainFrame.Size = UDim2.new(0, 360, 0, 480)
mainFrame.Position = UDim2.new(1, -380, 0.5, -240)
mainFrame.BackgroundColor3 = THEME.Bg
mainFrame.BorderSizePixel = 0
mainFrame.Active = true
mainFrame.Draggable = true
mainFrame.Parent = screenGui

local corner = Instance.new("UICorner")
corner.CornerRadius = UDim.new(0, 12)
corner.Parent = mainFrame

local stroke = Instance.new("UIStroke")
stroke.Color = Color3.fromRGB(55, 62, 78)
stroke.Thickness = 1.2
stroke.Parent = mainFrame

-- Encabezado
local header = Instance.new("Frame")
header.Size = UDim2.new(1, 0, 0, 50)
header.BackgroundColor3 = THEME.Header
header.BorderSizePixel = 0
header.Parent = mainFrame

local headerCorner = Instance.new("UICorner")
headerCorner.CornerRadius = UDim.new(0, 12)
headerCorner.Parent = header

local title = Instance.new("TextLabel")
title.Size = UDim2.new(1, -20, 1, 0)
title.Position = UDim2.new(0, 14, 0, 0)
title.BackgroundTransparency = 1
title.Text = "⚡ DETECTOR EN VIVO DE HUEVOS"
title.TextColor3 = THEME.Accent
title.Font = Enum.Font.GothamBold
title.TextSize = 14
title.TextXAlignment = Enum.TextXAlignment.Left
title.Parent = header

-- Lista desplazable para los huevos reales encontrados
local scrollList = Instance.new("ScrollingFrame")
scrollList.Size = UDim2.new(1, -20, 1, -70)
scrollList.Position = UDim2.new(0, 10, 0, 60)
scrollList.BackgroundTransparency = 1
scrollList.BorderSizePixel = 0
scrollList.ScrollBarThickness = 4
scrollList.ScrollBarImageColor3 = THEME.Accent
scrollList.AutomaticCanvasSize = Enum.AutomaticSize.Y
scrollList.Parent = mainFrame

local listLayout = Instance.new("UIListLayout")
listLayout.Padding = UDim.new(0, 8)
listLayout.SortOrder = Enum.SortOrder.LayoutOrder
listLayout.Parent = scrollList

------------------------------------------------------------------------
-- 4. FUNCIONES DE RASTREO VISUAL
------------------------------------------------------------------------
local function toggleTracker(eggInstance: Instance, part: BasePart, eggName: string)
    local entry = detectedEggs[eggInstance]
    if not entry then return end

    if entry.Billboard then
        entry.Billboard:Destroy()
        entry.Billboard = nil
        if entry.Highlight then
            entry.Highlight:Destroy()
            entry.Highlight = nil
        end
        return
    end

    local bb = Instance.new("BillboardGui")
    bb.Name = "StealIndicator_" .. eggName
    bb.Size = UDim2.new(0, 130, 0, 42)
    bb.StudsOffset = Vector3.new(0, 3, 0)
    bb.AlwaysOnTop = true
    bb.Adornee = part
    bb.Parent = screenGui

    local bbLabel = Instance.new("TextLabel")
    bbLabel.Size = UDim2.new(1, 0, 1, 0)
    bbLabel.BackgroundTransparency = 1
    bbLabel.Text = "🎯 [OBJETIVO]\n" .. eggName
    bbLabel.TextColor3 = THEME.Accent
    bbLabel.TextStrokeTransparency = 0.2
    bbLabel.Font = Enum.Font.GothamBold
    bbLabel.TextSize = 11
    bbLabel.Parent = bb

    local highlight = Instance.new("Highlight")
    highlight.FillColor = THEME.Accent
    highlight.OutlineColor = Color3.fromRGB(255, 255, 255)
    highlight.FillTransparency = 0.4
    highlight.OutlineTransparency = 0.2
    highlight.Adornee = eggInstance
    highlight.Parent = screenGui

    entry.Billboard = bb
    entry.Highlight = highlight
end

------------------------------------------------------------------------
-- 5. GESTIÓN DE INTERFAZ PARA CADA HUEVO REAL ENCONTRADO
------------------------------------------------------------------------
local function addEggCard(eggInstance: Instance, part: BasePart)
    if detectedEggs[eggInstance] then return end

    local eggName = eggInstance.Name

    local card = Instance.new("Frame")
    card.Size = UDim2.new(1, 0, 0, 64)
    card.BackgroundColor3 = THEME.CardBg
    card.BorderSizePixel = 0
    card.Parent = scrollList

    local cardCorner = Instance.new("UICorner")
    cardCorner.CornerRadius = UDim.new(0, 8)
    cardCorner.Parent = card

    local cardStroke = Instance.new("UIStroke")
    cardStroke.Color = THEME.Accent
    cardStroke.Thickness = 1
    cardStroke.Parent = card

    local nameLabel = Instance.new("TextLabel")
    nameLabel.Size = UDim2.new(0, 220, 0, 20)
    nameLabel.Position = UDim2.new(0, 12, 0, 10)
    nameLabel.BackgroundTransparency = 1
    nameLabel.Text = "🥚 " .. eggName
    nameLabel.TextColor3 = THEME.Text
    nameLabel.Font = Enum.Font.GothamBold
    nameLabel.TextSize = 13
    nameLabel.TextXAlignment = Enum.TextXAlignment.Left
    nameLabel.TextTruncate = Enum.TextTruncate.AtEnd
    nameLabel.Parent = card

    local distLabel = Instance.new("TextLabel")
    distLabel.Size = UDim2.new(0, 220, 0, 18)
    distLabel.Position = UDim2.new(0, 12, 0, 32)
    distLabel.BackgroundTransparency = 1
    distLabel.Text = "📍 Calculando distancia..."
    distLabel.TextColor3 = THEME.Success
    distLabel.Font = Enum.Font.Gotham
    distLabel.TextSize = 11
    distLabel.TextXAlignment = Enum.TextXAlignment.Left
    distLabel.Parent = card

    local trackBtn = Instance.new("TextButton")
    trackBtn.Size = UDim2.new(0, 78, 0, 32)
    trackBtn.Position = UDim2.new(1, -88, 0.5, -16)
    trackBtn.BackgroundColor3 = THEME.Accent
    trackBtn.Text = "RASTREAR"
    trackBtn.TextColor3 = Color3.fromRGB(20, 20, 20)
    trackBtn.Font = Enum.Font.GothamBold
    trackBtn.TextSize = 10
    trackBtn.BorderSizePixel = 0
    trackBtn.Parent = card

    local btnCorner = Instance.new("UICorner")
    btnCorner.CornerRadius = UDim.new(0, 6)
    btnCorner.Parent = trackBtn

    trackBtn.MouseButton1Click:Connect(function()
        if part and part.Parent then
            toggleTracker(eggInstance, part, eggName)
        end
    end)

    detectedEggs[eggInstance] = {
        Card = card,
        DistLabel = distLabel,
        TargetInstance = eggInstance,
        TargetPart = part,
        Billboard = nil,
        Highlight = nil,
    }
end

local function removeEggCard(eggInstance: Instance)
    local entry = detectedEggs[eggInstance]
    if entry then
        if entry.Billboard then entry.Billboard:Destroy() end
        if entry.Highlight then entry.Highlight:Destroy() end
        entry.Card:Destroy()
        detectedEggs[eggInstance] = nil
    end
end

------------------------------------------------------------------------
-- 6. ESCANEO DINÁMICO EN TIEMPO REAL (Busca objetos reales con "Egg" en el nombre)
------------------------------------------------------------------------
local function scanWorkspaceForEggs()
    local activeInstances = {}

    for _, desc in ipairs(workspace:GetDescendants()) do
        -- Filtra por nombre real que contenga "egg" (ajusta esto si el juego usa otro término)
        if desc:IsA("Model") or desc:IsA("BasePart") then
            if string.find(string.lower(desc.Name), "egg") then
                local part = desc:IsA("BasePart") and desc or (desc:IsA("Model") and (desc.PrimaryPart or desc:FindFirstChildWhichIsA("BasePart")))
                if part then
                    activeInstances[desc] = part
                    addEggCard(desc, part)
                end
            end
        end
    end

    -- Remover de la lista los huevos que ya desaparecieron del mapa
    for eggInst, _ in pairs(detectedEggs) do
        if not activeInstances[eggInst] or not eggInst.Parent then
            removeEggCard(eggInst)
        end
    end
end

------------------------------------------------------------------------
-- 7. BUCLE PRINCIPAL DE ACTUALIZACIÓN
------------------------------------------------------------------------
local scanTimer = 0
local distTimer = 0

RunService.RenderStepped:Connect(function(dt)
    scanTimer += dt
    distTimer += dt

    -- Escanear nuevos huevos en el mapa cada 1 segundo
    if scanTimer >= 1.0 then
        scanTimer = 0
        pcall(scanWorkspaceForEggs)
    end

    -- Actualizar distancias en vivo cada 0.15 segundos
    if distTimer >= 0.15 then
        distTimer = 0
        local char = localPlayer.Character
        local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?

        for _, entry in pairs(detectedEggs) do
            if entry.TargetPart and entry.TargetPart.Parent and root then
                local dist = (root.Position - entry.TargetPart.Position).Magnitude
                entry.DistLabel.Text = string.format("📍 Distancia: %.0f studs", dist)
                
                if entry.Billboard then
                    local lbl = entry.Billboard:FindFirstChildWhichIsA("TextLabel")
                    if lbl then
                        lbl.Text = string.format("🎯 [OBJETIVO]\n%s (%.0f studs)", entry.TargetInstance.Name, dist)
                    end
                end
            else
                removeEggCard(entry.TargetInstance)
            end
        end
    end
end)

screenGui.Parent = playerGui
print("[Steal Panel] Escáner en tiempo real de huevos reales activado.")
