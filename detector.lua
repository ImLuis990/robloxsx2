--!strict
--[[
    ========================================================================
    SISTEMA DE IDENTIFICACIÓN Y REGISTRO DE HUEVOS CON PANEL DE COPIA
    ========================================================================
    - Identifica huevo por huevo (desofuscando hashes de Workspace.AreaEggSlotsClient).
    - Cruza los datos con ReplicatedStorage.Data.Assets y biomas de GuardAreas.
    - Genera una ventana emergente en pantalla con un TextBox interactivo listo
      para seleccionar y copiar con Ctrl+A / Ctrl+C sin tocar la consola.
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local HttpService = game:GetService("HttpService")

local localPlayer = Players.LocalPlayer
local playerGui = localPlayer:WaitForChild("PlayerGui")

------------------------------------------------------------------------
-- 1. CONEXIÓN CON LOS ARCHIVOS INTERNOS DEL JUEGO
------------------------------------------------------------------------
local AssetsData: any = nil
local FieldReader: any = nil

pcall(function()
    local dataFolder = ReplicatedStorage:FindFirstChild("Data")
    local assetsModule = dataFolder and dataFolder:FindFirstChild("Assets")
    if assetsModule and assetsModule:IsA("ModuleScript") then
        AssetsData = require(assetsModule)
    end
end)

pcall(function()
    for _, desc in ipairs(ReplicatedStorage:GetDescendants()) do
        if desc:IsA("ModuleScript") and (desc.Name == "AreaEggsController" or desc.Name == "EggWorld" or desc.Name == "EggRecords") then
            local success, mod = pcall(require, desc)
            if success and type(mod) == "table" and (mod.ReadFieldEgg or mod.ReadFieldEggs) then
                FieldReader = mod
                break
            end
        end
    end
end)

------------------------------------------------------------------------
-- 2. BASE DE DATOS LOCAL
------------------------------------------------------------------------
type IdentifiedEgg = {
    UID: string,
    DisplayName: string,
    Category: string,
    Rarity: string,
    Area: string,
    MeshId: string,
    TextureId: string,
    PerSecond: string,
    Multiplier: string,
    Status: "En Mapa" | "En Posesion" | "En Base" | "Recolectado",
    LastSeenPosition: {X: number, Y: number, Z: number},
    DiscoveredAt: number,
}

local EggDatabase: {[string]: IdentifiedEgg} = {}
local knownCount = 0

------------------------------------------------------------------------
-- 3. CACHE GEOGRÁFICO DE ÁREAS (GUARD AREAS)
------------------------------------------------------------------------
local areaBounds: {[string]: BasePart} = {}

local function cacheAreas()
    local world = workspace:FindFirstChild("World")
    local areas = world and world:FindFirstChild("Areas")
    local guardAreas = areas and areas:FindFirstChild("GuardAreas")

    if guardAreas then
        for _, area in ipairs(guardAreas:GetChildren()) do
            local bounds = area:FindFirstChild("Bounds") or area:FindFirstChildWhichIsA("BasePart")
            if bounds and bounds:IsA("BasePart") then
                areaBounds[area.Name] = bounds
            end
        end
    end
end
cacheAreas()

local function resolveAreaName(pos: Vector3): string
    for areaName, part in pairs(areaBounds) do
        local localPos = part.CFrame:PointToObjectSpace(pos)
        local half = part.Size / 2
        if math.abs(localPos.X) <= half.X and math.abs(localPos.Z) <= half.Z then
            return areaName
        end
    end
    return "Desconocida / Neutral"
end

------------------------------------------------------------------------
-- 4. MOTOR DE IDENTIFICACIÓN
------------------------------------------------------------------------
local function extractMeshMetadata(model: Instance): (string, string, BasePart?)
    local targetPart: BasePart? = nil
    local meshId = "N/A"
    local textureId = "N/A"

    for _, desc in ipairs(model:GetDescendants()) do
        if desc:IsA("MeshPart") then
            targetPart = desc
            meshId = desc.MeshId
            textureId = desc.TextureID
            break
        elseif desc:IsA("SpecialMesh") then
            targetPart = desc.Parent :: BasePart?
            meshId = desc.MeshId
            textureId = desc.TextureId
            break
        elseif desc:IsA("BasePart") and not targetPart then
            targetPart = desc
        end
    end

    return meshId, textureId, targetPart
end

local function identifyEgg(model: Instance): IdentifiedEgg?
    local uid = model.Name
    local meshId, textureId, targetPart = extractMeshMetadata(model)
    local pos = targetPart and targetPart.Position or Vector3.zero
    local area = resolveAreaName(pos)

    local category = "Desconocido"
    local displayName = "Huevo #" .. string.sub(uid, 1, 6)
    local rarity = "Común"
    local perSec = "-- /s"
    local multi = "x1.0"

    -- 1. Consultar FieldReader del juego
    if FieldReader and FieldReader.ReadFieldEgg then
        local ok, record = pcall(FieldReader.ReadFieldEgg, uid)
        if ok and record then
            if record.AssetCategory then category = tostring(record.AssetCategory) end
            if record.AreaId then area = tostring(record.AreaId) end
            if record.BaseMutation and record.BaseMutation ~= "" then
                displayName = string.format("%s (%s)", category, tostring(record.BaseMutation))
            else
                displayName = category
            end
        end
    end

    -- 2. Consultar AssetsData.Directory
    if AssetsData and AssetsData.Directory and AssetsData.Directory[category] then
        local entry = AssetsData.Directory[category]
        if entry.DisplayName and entry.DisplayName ~= "" then
            displayName = entry.DisplayName
        end
        if entry.Rarity then rarity = tostring(entry.Rarity) end
        if entry.BaseEarnings then perSec = tostring(entry.BaseEarnings) .. " /s" end
        if entry.Multiplier then multi = "x" .. tostring(entry.Multiplier) end
    end

    -- 3. Si es FirstAreaEgg
    if string.find(uid, "FirstAreaEgg_") then
        local z, s = string.match(uid, "_([%a%d]+):Slot_(%d+)")
        if z then area = z end
        displayName = string.format("Huevo Principal [%s - Slot %s]", area, s or "1")
    end

    -- 4. Estado
    local status: "En Mapa" | "En Posesion" | "En Base" | "Recolectado" = "En Mapa"
    if model:FindFirstChild("PlacedEggPrompt", true) then
        status = "En Base"
    elseif model:FindFirstAncestorWhichIsA("Player") then
        status = "En Posesion"
    end

    local eggData: IdentifiedEgg = {
        UID = uid,
        DisplayName = displayName,
        Category = category,
        Rarity = rarity,
        Area = area,
        MeshId = meshId,
        TextureId = textureId,
        PerSecond = perSec,
        Multiplier = multi,
        Status = status,
        LastSeenPosition = {
            X = math.floor(pos.X * 10) / 10,
            Y = math.floor(pos.Y * 10) / 10,
            Z = math.floor(pos.Z * 10) / 10,
        },
        DiscoveredAt = os.time(),
    }

    if not EggDatabase[uid] then
        knownCount += 1
    end

    EggDatabase[uid] = eggData
    return eggData
end

------------------------------------------------------------------------
-- 5. INTERFAZ GRÁFICA CON PANEL DE COPIA EN PANTALLA
------------------------------------------------------------------------
local GUI_NAME = "EggDatabaseManager_UI"
local prev = playerGui:FindFirstChild(GUI_NAME)
if prev then prev:Destroy() end

local screenGui = Instance.new("ScreenGui")
screenGui.Name = GUI_NAME
screenGui.ResetOnSpawn = false
screenGui.Parent = playerGui

-- Ventana Principal
local mainFrame = Instance.new("Frame")
mainFrame.Name = "MainFrame"
mainFrame.Size = UDim2.new(0, 390, 0, 480)
mainFrame.Position = UDim2.new(0, 25, 0.5, -240)
mainFrame.BackgroundColor3 = Color3.fromRGB(22, 25, 32)
mainFrame.BorderSizePixel = 0
mainFrame.Active = true
mainFrame.Draggable = true
mainFrame.Parent = screenGui

local corner = Instance.new("UICorner")
corner.CornerRadius = UDim.new(0, 10)
corner.Parent = mainFrame

local stroke = Instance.new("UIStroke")
stroke.Color = Color3.fromRGB(60, 68, 85)
stroke.Thickness = 1.2
stroke.Parent = mainFrame

-- Cabecera
local header = Instance.new("Frame")
header.Size = UDim2.new(1, 0, 0, 48)
header.BackgroundColor3 = Color3.fromRGB(28, 32, 42)
header.BorderSizePixel = 0
header.Parent = mainFrame

local headerCorner = Instance.new("UICorner")
headerCorner.CornerRadius = UDim.new(0, 10)
headerCorner.Parent = header

local title = Instance.new("TextLabel")
title.Size = UDim2.new(1, -130, 1, 0)
title.Position = UDim2.new(0, 14, 0, 0)
title.BackgroundTransparency = 1
title.Text = "📖 Diccionario de Huevos"
title.TextColor3 = Color3.fromRGB(255, 195, 45)
title.Font = Enum.Font.GothamBold
title.TextSize = 13
title.TextXAlignment = Enum.TextXAlignment.Left
title.Parent = header

-- Botón para Abrir el Panel de Copia
local openCopyBtn = Instance.new("TextButton")
openCopyBtn.Size = UDim2.new(0, 110, 0, 28)
openCopyBtn.Position = UDim2.new(1, -120, 0.5, -14)
openCopyBtn.BackgroundColor3 = Color3.fromRGB(45, 140, 255)
openCopyBtn.Text = "📋 Copiar Datos"
openCopyBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
openCopyBtn.Font = Enum.Font.GothamBold
openCopyBtn.TextSize = 11
openCopyBtn.BorderSizePixel = 0
openCopyBtn.Parent = header

local expCorner = Instance.new("UICorner")
expCorner.CornerRadius = UDim.new(0, 6)
expCorner.Parent = openCopyBtn

-- Barra de estado
local statsBar = Instance.new("TextLabel")
statsBar.Size = UDim2.new(1, -20, 0, 24)
statsBar.Position = UDim2.new(0, 10, 0, 54)
statsBar.BackgroundColor3 = Color3.fromRGB(30, 35, 46)
statsBar.TextColor3 = Color3.fromRGB(200, 205, 220)
statsBar.Font = Enum.Font.GothamMedium
statsBar.TextSize = 11
statsBar.Text = "Huevos registrados: 0"
statsBar.Parent = mainFrame

local statsCorner = Instance.new("UICorner")
statsCorner.CornerRadius = UDim.new(0, 6)
statsCorner.Parent = statsBar

-- Lista scrolleable
local scroll = Instance.new("ScrollingFrame")
scroll.Size = UDim2.new(1, -20, 1, -95)
scroll.Position = UDim2.new(0, 10, 0, 85)
scroll.BackgroundTransparency = 1
scroll.BorderSizePixel = 0
scroll.ScrollBarThickness = 3
scroll.ScrollBarImageColor3 = Color3.fromRGB(255, 195, 45)
scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
scroll.Parent = mainFrame

local listLayout = Instance.new("UIListLayout")
listLayout.Padding = UDim.new(0, 6)
listLayout.SortOrder = Enum.SortOrder.LayoutOrder
listLayout.Parent = scroll

------------------------------------------------------------------------
-- 6. MODAL / VENTANA EMERGENTE PARA COPIAR TODO EN PANTALLA
------------------------------------------------------------------------
local copyModal = Instance.new("Frame")
copyModal.Name = "CopyModal"
copyModal.Size = UDim2.new(0, 420, 0, 380)
copyModal.Position = UDim2.new(0.5, -210, 0.5, -190)
copyModal.BackgroundColor3 = Color3.fromRGB(18, 20, 26)
copyModal.BorderSizePixel = 0
copyModal.Active = true
copyModal.Draggable = true
copyModal.Visible = false
copyModal.ZIndex = 10
copyModal.Parent = screenGui

local modalCorner = Instance.new("UICorner")
modalCorner.CornerRadius = UDim.new(0, 10)
modalCorner.Parent = copyModal

local modalStroke = Instance.new("UIStroke")
modalStroke.Color = Color3.fromRGB(70, 80, 105)
modalStroke.Thickness = 1.5
modalStroke.Parent = copyModal

local modalHeader = Instance.new("Frame")
modalHeader.Size = UDim2.new(1, 0, 0, 40)
modalHeader.BackgroundColor3 = Color3.fromRGB(26, 30, 40)
modalHeader.BorderSizePixel = 0
modalHeader.ZIndex = 11
modalHeader.Parent = copyModal

local mCorner = Instance.new("UICorner")
mCorner.CornerRadius = UDim.new(0, 10)
mCorner.Parent = modalHeader

local modalTitle = Instance.new("TextLabel")
modalTitle.Size = UDim2.new(1, -60, 1, 0)
modalTitle.Position = UDim2.new(0, 12, 0, 0)
modalTitle.BackgroundTransparency = 1
modalTitle.Text = "📋 Copiar Registro Completo de Huevos"
modalTitle.TextColor3 = Color3.fromRGB(240, 240, 240)
modalTitle.Font = Enum.Font.GothamBold
modalTitle.TextSize = 12
modalTitle.TextXAlignment = Enum.TextXAlignment.Left
modalTitle.ZIndex = 12
modalTitle.Parent = modalHeader

local closeBtn = Instance.new("TextButton")
closeBtn.Size = UDim2.new(0, 30, 0, 26)
closeBtn.Position = UDim2.new(1, -36, 0.5, -13)
closeBtn.BackgroundColor3 = Color3.fromRGB(220, 50, 50)
closeBtn.Text = "✕"
closeBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
closeBtn.Font = Enum.Font.GothamBold
closeBtn.TextSize = 12
closeBtn.BorderSizePixel = 0
closeBtn.ZIndex = 12
closeBtn.Parent = modalHeader

local cBtnCorner = Instance.new("UICorner")
cBtnCorner.CornerRadius = UDim.new(0, 6)
cBtnCorner.Parent = closeBtn

local helperText = Instance.new("TextLabel")
helperText.Size = UDim2.new(1, -24, 0, 22)
helperText.Position = UDim2.new(0, 12, 0, 46)
helperText.BackgroundTransparency = 1
helperText.Text = "Haz clic en el cuadro de abajo, presiona Ctrl+A y luego Ctrl+C:"
helperText.TextColor3 = Color3.fromRGB(180, 190, 210)
helperText.Font = Enum.Font.Gotham
helperText.TextSize = 11
helperText.TextXAlignment = Enum.TextXAlignment.Left
helperText.ZIndex = 11
helperText.Parent = copyModal

-- TextBox grande con el contenido generado
local exportTextBox = Instance.new("TextBox")
exportTextBox.Size = UDim2.new(1, -24, 1, -80)
exportTextBox.Position = UDim2.new(0, 12, 0, 70)
exportTextBox.BackgroundColor3 = Color3.fromRGB(25, 28, 38)
exportTextBox.TextColor3 = Color3.fromRGB(255, 215, 80)
exportTextBox.Font = Enum.Font.Code
exportTextBox.TextSize = 11
exportTextBox.TextXAlignment = Enum.TextXAlignment.Left
exportTextBox.TextYAlignment = Enum.TextYAlignment.Top
exportTextBox.ClearTextOnFocus = false
exportTextBox.MultiLine = true
exportTextBox.TextEditable = false -- Solo lectura para no borrar por accidente
exportTextBox.ZIndex = 11
exportTextBox.Parent = copyModal

local tbCorner = Instance.new("UICorner")
tbCorner.CornerRadius = UDim.new(0, 6)
tbCorner.Parent = exportTextBox

-- Abrir el modal y generar el texto completo
openCopyBtn.MouseButton1Click:Connect(function()
    local serialized = HttpService:JSONEncode(EggDatabase)
    exportTextBox.Text = serialized
    copyModal.Visible = true
    exportTextBox:CaptureFocus()
end)

closeBtn.MouseButton1Click:Connect(function()
    copyModal.Visible = false
end)

------------------------------------------------------------------------
-- 7. REFRESH DE LA LISTA EN PANTALLA
------------------------------------------------------------------------
local renderedCards: {[string]: Frame} = {}

local function refreshUI()
    statsBar.Text = string.format("Huevos registrados: %d", knownCount)

    for uid, egg in pairs(EggDatabase) do
        local card = renderedCards[uid]
        if not card then
            card = Instance.new("Frame")
            card.Name = uid
            card.Size = UDim2.new(1, 0, 0, 50)
            card.BackgroundColor3 = Color3.fromRGB(30, 34, 45)
            card.BorderSizePixel = 0
            card.Parent = scroll

            local cCorner = Instance.new("UICorner")
            cCorner.CornerRadius = UDim.new(0, 6)
            cCorner.Parent = card

            local nameLbl = Instance.new("TextLabel")
            nameLbl.Name = "Name"
            nameLbl.Size = UDim2.new(1, -80, 0, 18)
            nameLbl.Position = UDim2.new(0, 10, 0, 6)
            nameLbl.BackgroundTransparency = 1
            nameLbl.TextColor3 = Color3.fromRGB(255, 255, 255)
            nameLbl.Font = Enum.Font.GothamBold
            nameLbl.TextSize = 12
            nameLbl.TextXAlignment = Enum.TextXAlignment.Left
            nameLbl.TextTruncate = Enum.TextTruncate.AtEnd
            nameLbl.Parent = card

            local detailsLbl = Instance.new("TextLabel")
            detailsLbl.Name = "Details"
            detailsLbl.Size = UDim2.new(1, -80, 0, 16)
            detailsLbl.Position = UDim2.new(0, 10, 0, 26)
            detailsLbl.BackgroundTransparency = 1
            detailsLbl.TextColor3 = Color3.fromRGB(160, 168, 185)
            detailsLbl.Font = Enum.Font.Gotham
            detailsLbl.TextSize = 10
            detailsLbl.TextXAlignment = Enum.TextXAlignment.Left
            detailsLbl.Parent = card

            local statusBadge = Instance.new("TextLabel")
            statusBadge.Name = "Status"
            statusBadge.Size = UDim2.new(0, 68, 0, 22)
            statusBadge.Position = UDim2.new(1, -74, 0.5, -11)
            statusBadge.BackgroundColor3 = Color3.fromRGB(45, 180, 100)
            statusBadge.TextColor3 = Color3.fromRGB(255, 255, 255)
            statusBadge.Font = Enum.Font.GothamBold
            statusBadge.TextSize = 9
            statusBadge.Parent = card

            local sCorner = Instance.new("UICorner")
            sCorner.CornerRadius = UDim.new(0, 4)
            sCorner.Parent = statusBadge

            renderedCards[uid] = card
        end

        local nameLbl = card:FindFirstChild("Name") :: TextLabel
        local detailsLbl = card:FindFirstChild("Details") :: TextLabel
        local statusBadge = card:FindFirstChild("Status") :: TextLabel

        if nameLbl then nameLbl.Text = string.format("🥚 %s", egg.DisplayName) end
        if detailsLbl then
            detailsLbl.Text = string.format("📍 %s | Hash: #%s | %s", egg.Area, string.sub(uid, 1, 6), egg.PerSecond)
        end
        if statusBadge then
            statusBadge.Text = egg.Status
            statusBadge.BackgroundColor3 = (egg.Status == "En Mapa") and Color3.fromRGB(45, 180, 100) or Color3.fromRGB(220, 140, 30)
        end
    end
end

------------------------------------------------------------------------
-- 8. ESCANEO CONTINUO Y REGISTRO EN TIEMPO REAL
------------------------------------------------------------------------
local function inspectInstance(inst: Instance)
    if (inst.Parent and inst.Parent.Name == "AreaEggSlotsClient")
        or inst:FindFirstChild("CarryAreaEgg", true) 
        or string.find(inst.Name, "FirstAreaEgg_") 
        or (#inst.Name == 32 and string.match(inst.Name, "^[a-f0-9]+$")) then
        
        identifyEgg(inst)
    end
end

local slots = workspace:FindFirstChild("AreaEggSlotsClient")
if slots then
    for _, egg in ipairs(slots:GetChildren()) do
        inspectInstance(egg)
    end
end
for _, desc in ipairs(workspace:GetDescendants()) do
    inspectInstance(desc)
end

workspace.DescendantAdded:Connect(function(desc)
    task.wait(0.08)
    inspectInstance(desc)
    refreshUI()
end)

-- Bucle de actualización cada 1s
task.spawn(function()
    while true do
        task.wait(1)
        for uid, egg in pairs(EggDatabase) do
            local found = false
            if slots and slots:FindFirstChild(uid) then
                found = true
            else
                for _, desc in ipairs(workspace:GetDescendants()) do
                    if desc.Name == uid then
                        found = true
                        break
                    end
                end
            end
            if not found and egg.Status == "En Mapa" then
                egg.Status = "Recolectado"
            end
        end
        refreshUI()
    end
end)

refreshUI()
