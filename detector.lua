--!strict
--[[
    ========================================================================
    ESP DESOFUSCADOR DE HUEVOS (ÁREA / FIELD / SLOTS)
    ========================================================================
    Detecta los huevos reales del juego incluso si sus nombres están
    ofuscados como hashes de 32 dígitos hexadecimales (UIDs) o FirstAreaEgg.

    Ubicación del juego:
      - Workspace.AreaEggSlotsClient (Contenedor oficial de los huevos en el mapa)
      - ProximityPrompt: CarryAreaEgg (ActionText: Steal)
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local localPlayer = Players.LocalPlayer
local playerGui = localPlayer:WaitForChild("PlayerGui")

------------------------------------------------------------------------
-- 1. CONFIGURACIÓN DEL SISTEMA
------------------------------------------------------------------------
local CONFIG = {
    GuiIdentifier = "GamePrecise_EggESP_V2",

    HighlightColor = Color3.fromRGB(255, 195, 45),       -- Oro brillante
    HighlightOutline = Color3.fromRGB(255, 255, 255),
    FillTransparency = 0.45,
    OutlineTransparency = 0.1,

    TextSize = 12,
    StudsOffset = Vector3.new(0, 3.2, 0),
    MaxRenderDistance = 3500,
    UpdateInterval = 0.08,
}

------------------------------------------------------------------------
-- 2. LIMPIEZA PREVENTIVA
------------------------------------------------------------------------
local function cleanupPreviousGui()
    local existing = playerGui:FindFirstChild(CONFIG.GuiIdentifier)
    if existing then
        existing:Destroy()
    end
end
cleanupPreviousGui()

local espFolder = Instance.new("Folder")
espFolder.Name = CONFIG.GuiIdentifier
espFolder.Parent = playerGui

------------------------------------------------------------------------
-- 3. ESTADO Y RESOLVEDOR DE NOMBRES
------------------------------------------------------------------------
type EggRecord = {
    Instance: Instance,
    TargetPart: BasePart,
    Billboard: BillboardGui,
    Label: TextLabel,
    Highlight: Highlight,
    DisplayName: string,
    AncestryConn: RBXScriptConnection,
}

local trackedRegistry: {[Instance]: EggRecord} = {}

-- Intentar vincular con el lector de datos interno del cliente si existe
local FieldEggReader: any = nil
pcall(function()
    for _, desc in ipairs(ReplicatedStorage:GetDescendants()) do
        if desc:IsA("ModuleScript") and (desc.Name == "AreaEggsController" or desc.Name == "EggWorld" or desc.Name == "EggRecords") then
            local success, mod = pcall(require, desc)
            if success and type(mod) == "table" and (mod.ReadFieldEgg ~= nil or mod.ReadFieldEggs ~= nil) then
                FieldEggReader = mod
                break
            end
        end
    end
end)

-- Resuelve el nombre legible a partir de un hash o FirstAreaEgg
local function resolveEggDisplayName(model: Instance): string
    local name = model.Name

    -- 1. Si el módulo interno puede resolver el Uid a su AssetCategory
    if FieldEggReader and FieldEggReader.ReadFieldEgg then
        local success, record = pcall(FieldEggReader.ReadFieldEgg, name)
        if success and record and record.AssetCategory then
            local cat = tostring(record.AssetCategory)
            if record.BaseMutation and record.BaseMutation ~= "" then
                return string.format("✨ %s (%s)", cat, tostring(record.BaseMutation))
            end
            return "🥚 " .. cat
        end
    end

    -- 2. Si es FirstAreaEgg (ej. FirstAreaEgg_11891409261_5978247_Forest:Slot_001)
    if string.find(name, "FirstAreaEgg_") then
        local zone, slot = string.match(name, "_([%a%d]+):Slot_(%d+)")
        if zone and slot then
            return string.format("🥚 Huevo %s [Slot %s]", zone, slot)
        end
        return "🥚 Huevo Principal"
    end

    -- 3. Si es un hash MD5 de 32 caracteres (ej. 6874a5ca5fae4fdea5c216df613054f6)
    if string.match(name, "^[a-f0-9][a-f0-9][a-f0-9][a-f0-9][a-f0-9][a-f0-9]") then
        local shortId = string.sub(name, 1, 6)
        -- Si dentro tiene una mesh o prompt de robo
        return string.format("🥚 Huevo [#%s]", shortId)
    end

    return "🥚 " .. name
end

------------------------------------------------------------------------
-- 4. DETECTOR DE HUEVOS OFUSCADOS EN WORKSPACE
------------------------------------------------------------------------

-- Comprueba si el objeto es un modelo de huevo válido en el mapa
local function isOfuscatedEggModel(instance: Instance): (boolean, BasePart?)
    if not (instance:IsA("Model") or instance:IsA("BasePart")) then
        return false, nil
    end

    -- Ignorar si es el personaje de algún jugador
    if instance:FindFirstAncestorWhichIsA("Player") or instance:FindFirstChildOfClass("Humanoid") then
        return false, nil
    end

    local isEgg = false
    local name = instance.Name

    -- CRITERIO A: Está dentro de la carpeta oficial "AreaEggSlotsClient"
    local parent = instance.Parent
    if parent and parent.Name == "AreaEggSlotsClient" then
        isEgg = true
    end

    -- CRITERIO B: Tiene el ProximityPrompt nativo de robo "CarryAreaEgg" o "CarryHalloweenEgg"
    if not isEgg and (instance:FindFirstChild("CarryAreaEgg", true) or instance:FindFirstChild("CarryHalloweenEgg", true)) then
        isEgg = true
    end

    -- CRITERIO C: Patrón de nombre FirstAreaEgg_ o Hash hexadecimal de 32 dígitos
    if not isEgg then
        if string.find(name, "FirstAreaEgg_") then
            isEgg = true
        elseif #name == 32 and string.match(name, "^[a-f0-9]+$") then
            -- Asegurarse de que contenga una pieza física (meshpart o basepart)
            if instance:FindFirstChildWhichIsA("BasePart") then
                isEgg = true
            end
        end
    end

    if not isEgg then
        return false, nil
    end

    -- Descartar si tiene PlacedEggPrompt (ya está colocado en base de jugador)
    if instance:FindFirstChild("PlacedEggPrompt", true) or instance:FindFirstChild("PlacedEggBillboard", true) then
        return false, nil
    end

    -- Obtener la parte física representativa
    local basePart: BasePart? = nil
    if instance:IsA("BasePart") then
        basePart = instance
    elseif instance:IsA("Model") then
        basePart = instance.PrimaryPart 
            or instance:FindFirstChild("untitled.001") :: BasePart?
            or instance:FindFirstChildWhichIsA("MeshPart")
            or instance:FindFirstChildWhichIsA("BasePart")
    end

    if basePart then
        return true, basePart
    end

    return false, nil
end

------------------------------------------------------------------------
-- 5. CREACIÓN Y DESTRUCCIÓN DE VISUALES (ESP)
------------------------------------------------------------------------
local function removeVisuals(targetInstance: Instance)
    local entry = trackedRegistry[targetInstance]
    if not entry then return end

    if entry.AncestryConn then
        entry.AncestryConn:Disconnect()
    end
    if entry.Billboard then
        entry.Billboard:Destroy()
    end
    if entry.Highlight then
        entry.Highlight:Destroy()
    end

    trackedRegistry[targetInstance] = nil
end

local function createVisuals(targetInstance: Instance, targetPart: BasePart)
    if trackedRegistry[targetInstance] then return end

    local displayName = resolveEggDisplayName(targetInstance)

    -- 1. Highlight (silueta visible a través de paredes)
    local highlight = Instance.new("Highlight")
    highlight.Name = "ESP_Highlight_" .. targetInstance.Name
    highlight.Adornee = targetInstance
    highlight.FillColor = CONFIG.HighlightColor
    highlight.OutlineColor = CONFIG.HighlightOutline
    highlight.FillTransparency = CONFIG.FillTransparency
    highlight.OutlineTransparency = CONFIG.OutlineTransparency
    highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
    highlight.Parent = espFolder

    -- 2. BillboardGui (nombre y distancia flotante)
    local billboard = Instance.new("BillboardGui")
    billboard.Name = "ESP_Billboard_" .. targetInstance.Name
    billboard.Adornee = targetPart
    billboard.Size = UDim2.new(0, 150, 0, 38)
    billboard.StudsOffset = CONFIG.StudsOffset
    billboard.AlwaysOnTop = true
    billboard.MaxDistance = CONFIG.MaxRenderDistance
    billboard.Parent = espFolder

    local label = Instance.new("TextLabel")
    label.Size = UDim2.new(1, 0, 1, 0)
    label.BackgroundTransparency = 1
    label.Font = Enum.Font.GothamBold
    label.TextSize = CONFIG.TextSize
    label.TextColor3 = CONFIG.HighlightColor
    label.TextStrokeTransparency = 0.2
    label.TextStrokeColor3 = Color3.fromRGB(15, 15, 20)
    label.Text = string.format("%s\n[-- studs]", displayName)
    label.Parent = billboard

    -- Limpieza reactiva si el huevo es recogido o destruido
    local ancestryConn: RBXScriptConnection
    ancestryConn = targetInstance.AncestryChanged:Connect(function(_, parent)
        if not parent or not targetInstance:IsDescendantOf(workspace) then
            removeVisuals(targetInstance)
        elseif targetInstance:FindFirstChild("PlacedEggPrompt", true) then
            removeVisuals(targetInstance)
        end
    end)

    trackedRegistry[targetInstance] = {
        Instance = targetInstance,
        TargetPart = targetPart,
        Billboard = billboard,
        Label = label,
        Highlight = highlight,
        DisplayName = displayName,
        AncestryConn = ancestryConn,
    }
end

local function evaluateInstance(instance: Instance)
    local isValid, targetPart = isOfuscatedEggModel(instance)
    if isValid and targetPart then
        createVisuals(instance, targetPart)
    end
end

------------------------------------------------------------------------
-- 6. ESCANEO Y DETECCIÓN EN TIEMPO REAL
------------------------------------------------------------------------

-- 1. Escaneo prioritario dentro de AreaEggSlotsClient (si ya existe)
local clientFolder = workspace:FindFirstChild("AreaEggSlotsClient")
if clientFolder then
    for _, eggModel in ipairs(clientFolder:GetChildren()) do
        evaluateInstance(eggModel)
    end
end

-- 2. Escaneo general de todo el Workspace
for _, desc in ipairs(workspace:GetDescendants()) do
    evaluateInstance(desc)
end

-- 3. Detección reactiva cuando spawnean nuevos huevos ofuscados
workspace.DescendantAdded:Connect(function(desc)
    task.wait(0.08)
    evaluateInstance(desc)
end)

-- 4. Limpieza cuando se van
workspace.DescendantRemoving:Connect(function(desc)
    if trackedRegistry[desc] then
        removeVisuals(desc)
    end
end)

------------------------------------------------------------------------
-- 7. BUCLE DE DISTANCIAS EN VIVO
------------------------------------------------------------------------
local elapsed = 0

RunService.RenderStepped:Connect(function(dt: number)
    elapsed += dt
    if elapsed < CONFIG.UpdateInterval then return end
    elapsed = 0

    local character = localPlayer.Character
    local rootPart = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?

    for instance, entry in pairs(trackedRegistry) do
        if not instance.Parent or not entry.TargetPart.Parent then
            removeVisuals(instance)
            continue
        end

        if rootPart then
            local dist = (rootPart.Position - entry.TargetPart.Position).Magnitude
            entry.Label.Text = string.format("%s\n[%.0f studs]", entry.DisplayName, dist)
        else
            entry.Label.Text = string.format("%s\n[--]", entry.DisplayName)
        end
    end
end)

print("[ESP] Detector de huevos ofuscados cargado exitosamente.")
