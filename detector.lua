--!strict
--[[
    ========================================================================
    SISTEMA MODULAR DE ESP EXCLUSIVO PARA HUEVOS LIBRES EN EL MAPA
    ========================================================================
    Filtro estricto que ignora:
      - Botones de compra / Pads / Stands
      - Puntos de spawn / Waypoints
      - Huevos ya recolectados o colocados en bases / plots de jugadores
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local localPlayer = Players.LocalPlayer
local playerGui = localPlayer:WaitForChild("PlayerGui")

------------------------------------------------------------------------
-- 1. CONFIGURACIÓN Y LISTAS NEGRAS DE FILTRADO
------------------------------------------------------------------------
local CONFIG = {
    GuiIdentifier = "CustomVisualESP_Container",

    -- Palabras clave positivas requeridas en el nombre
    Keywords = {"egg", "huevo"},

    -- Palabras negras: si el objeto contiene alguna de estas, SE IGNORA
    BlacklistKeywords = {
        "button", "boton", "pad", "stand", "spawn", "spawner", "point", 
        "punto", "buy", "shop", "tienda", "prompt", "hitbox", "collider",
        "zone", "zona", "area", "teleport", "door", "puerta", "display"
    },

    -- Nombres de carpetas o ancestros prohibidos (bases de jugadores, tiendas, etc.)
    BlacklistAncestors = {
        "plot", "plots", "base", "bases", "tycoon", "tycoons", 
        "stand", "stands", "shop", "shops", "store", "incubator"
    },

    -- Visuales
    HighlightColor = Color3.fromRGB(255, 185, 45),
    HighlightOutline = Color3.fromRGB(255, 255, 255),
    FillTransparency = 0.5,
    OutlineTransparency = 0.1,
    TextSize = 12,
    StudsOffset = Vector3.new(0, 2.5, 0),
    UpdateInterval = 0.1,
}

------------------------------------------------------------------------
-- 2. LIMPIEZA PREVIA
------------------------------------------------------------------------
local function cleanupPreviousInstances()
    local existingContainer = playerGui:FindFirstChild(CONFIG.GuiIdentifier)
    if existingContainer then
        existingContainer:Destroy()
    end
end
cleanupPreviousInstances()

local espFolder = Instance.new("Folder")
espFolder.Name = CONFIG.GuiIdentifier
espFolder.Parent = playerGui

------------------------------------------------------------------------
-- 3. ESTADO
------------------------------------------------------------------------
type TrackedEntry = {
    Instance: Instance,
    TargetPart: BasePart,
    Billboard: BillboardGui,
    Label: TextLabel,
    Highlight: Highlight,
    AncestryConn: RBXScriptConnection,
}

local trackedRegistry: {[Instance]: TrackedEntry} = {}

------------------------------------------------------------------------
-- 4. FILTRADO ESTRICTO DE HUEVOS LIBRES
------------------------------------------------------------------------

-- Comprueba si el objeto pertenece a una base, plot o tienda de jugadores
local function isInBlacklistedAncestor(instance: Instance): boolean
    local current: Instance? = instance.Parent
    while current and current ~= workspace do
        local parentName = string.lower(current.Name)

        -- 1. Verificar nombres de carpetas de bases/plots
        for _, blackName in ipairs(CONFIG.BlacklistAncestors) do
            if string.find(parentName, blackName) then
                return true
            end
        end

        -- 2. Si la carpeta tiene un atributo o valor "Owner" (dueño de la base)
        if current:GetAttribute("Owner") or current:FindFirstChild("Owner") or current:FindFirstChild("OwnerValue") then
            return true
        end

        current = current.Parent
    end
    return false
end

-- Determina si es exactamente un huevo libre del mapa para robar/recoger
local function isValidFreeEgg(instance: Instance): (boolean, BasePart?)
    -- Solo nos interesan Models o BaseParts principales
    if not (instance:IsA("Model") or instance:IsA("BasePart")) then
        return false, nil
    end

    -- Descartar si pertenece al personaje de cualquier jugador
    if instance:FindFirstAncestorWhichIsA("Player") or instance:FindFirstChildOfClass("Humanoid") then
        return false, nil
    end

    -- Descartar si está en la base/plot de un jugador
    if isInBlacklistedAncestor(instance) then
        return false, nil
    end

    local nameLower = string.lower(instance.Name)

    -- Descartar si el nombre contiene palabras clave de botones, pads, spawns, etc.
    for _, blackWord in ipairs(CONFIG.BlacklistKeywords) do
        if string.find(nameLower, blackWord) then
            return false, nil
        end
    end

    -- Debe contener "egg" o "huevo"
    local hasKeyword = false
    for _, kw in ipairs(CONFIG.Keywords) do
        if string.find(nameLower, kw) then
            hasKeyword = true
            break
        end
    end

    if not hasKeyword then
        return false, nil
    end

    -- Si es un Modelo, asegurarse de que no sea una estación o máquina
    if instance:IsA("Model") then
        -- Si contiene partes que dicen "Base", "Stand" o "Pad", ignorar
        for _, child in ipairs(instance:GetChildren()) do
            local childName = string.lower(child.Name)
            if string.find(childName, "pad") or string.find(childName, "stand") then
                return false, nil
            end
        end
    end

    -- Obtener la parte física representativa
    local basePart: BasePart? = nil
    if instance:IsA("BasePart") then
        -- Si es una parte transparente invisible (ej. hitbox de zona), ignorar
        if instance.Transparency >= 0.95 and not instance:FindFirstChildOfClass("SpecialMesh") then
            return false, nil
        end
        basePart = instance
    elseif instance:IsA("Model") then
        basePart = instance.PrimaryPart or instance:FindFirstChildWhichIsA("BasePart")
    end

    if basePart then
        return true, basePart
    end

    return false, nil
end

------------------------------------------------------------------------
-- 5. CREACIÓN Y DESTRUCCIÓN DE ELEMENTOS VISUALES
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

    -- 1. Resaltado (Highlight)
    local highlight = Instance.new("Highlight")
    highlight.Name = "ESP_Highlight_" .. targetInstance.Name
    highlight.Adornee = targetInstance
    highlight.FillColor = CONFIG.HighlightColor
    highlight.OutlineColor = CONFIG.HighlightOutline
    highlight.FillTransparency = CONFIG.FillTransparency
    highlight.OutlineTransparency = CONFIG.OutlineTransparency
    highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
    highlight.Parent = espFolder

    -- 2. Marcador flotante (BillboardGui)
    local billboard = Instance.new("BillboardGui")
    billboard.Name = "ESP_Billboard_" .. targetInstance.Name
    billboard.Adornee = targetPart
    billboard.Size = UDim2.new(0, 130, 0, 36)
    billboard.StudsOffset = CONFIG.StudsOffset
    billboard.AlwaysOnTop = true
    billboard.MaxDistance = 2000
    billboard.Parent = espFolder

    local label = Instance.new("TextLabel")
    label.Size = UDim2.new(1, 0, 1, 0)
    label.BackgroundTransparency = 1
    label.Font = Enum.Font.GothamBold
    label.TextSize = CONFIG.TextSize
    label.TextColor3 = CONFIG.HighlightColor
    label.TextStrokeTransparency = 0.2
    label.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
    label.Text = string.format("🥚 %s\n[--]", targetInstance.Name)
    label.Parent = billboard

    -- 3. Limpieza automática si el huevo es recogido o destruido
    local ancestryConn: RBXScriptConnection
    ancestryConn = targetInstance.AncestryChanged:Connect(function(_, parent)
        if not parent or isInBlacklistedAncestor(targetInstance) then
            removeVisuals(targetInstance)
        end
    end)

    trackedRegistry[targetInstance] = {
        Instance = targetInstance,
        TargetPart = targetPart,
        Billboard = billboard,
        Label = label,
        Highlight = highlight,
        AncestryConn = ancestryConn,
    }
end

local function evaluateInstance(instance: Instance)
    local isValid, targetPart = isValidFreeEgg(instance)
    if isValid and targetPart then
        createVisuals(instance, targetPart)
    end
end

------------------------------------------------------------------------
-- 6. ESCANEO Y DETECCIÓN EN TIEMPO REAL
------------------------------------------------------------------------
-- Escaneo inicial
for _, desc in ipairs(workspace:GetDescendants()) do
    evaluateInstance(desc)
end

-- Cuando un nuevo huevo spawnea libre en el mapa
workspace.DescendantAdded:Connect(function(desc)
    task.wait(0.1)
    evaluateInstance(desc)
end)

-- Cuando un huevo es recogido o destruido
workspace.DescendantRemoving:Connect(function(desc)
    if trackedRegistry[desc] then
        removeVisuals(desc)
    end
end)

------------------------------------------------------------------------
-- 7. BUCLE DE DISTANCIAS
------------------------------------------------------------------------
local elapsed = 0

RunService.RenderStepped:Connect(function(dt: number)
    elapsed += dt
    if elapsed < CONFIG.UpdateInterval then return end
    elapsed = 0

    local character = localPlayer.Character
    local rootPart = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?

    for instance, entry in pairs(trackedRegistry) do
        -- Si el huevo fue colocado en una base mientras existía, removerlo
        if not instance.Parent or not entry.TargetPart.Parent or isInBlacklistedAncestor(instance) then
            removeVisuals(instance)
            continue
        end

        if rootPart then
            local dist = (rootPart.Position - entry.TargetPart.Position).Magnitude
            entry.Label.Text = string.format("🥚 %s\n[%.0f studs]", instance.Name, dist)
        end
    end
end)
