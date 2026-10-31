--!strict
--[[
    ========================================================================
    SISTEMA DE ESP EXCLUSIVO PARA HUEVOS LIBRES EN EL MAPA
    ========================================================================
    Entorno: Roblox Studio (LocalScript)
    Ubicación recomendada: StarterPlayer -> StarterPlayerScripts (o StarterGui)

    Filtro estricto que CORRIGE y DESMALLA:
      - Treadmills (cintas / caminadoras)
      - Egg Fuse Machines (máquinas de fusión)
      - Botones, Pads, Displays y Puntos de spawn
      - Huevos ya recolectados o colocados en bases/plots de jugadores
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local localPlayer = Players.LocalPlayer
local playerGui = localPlayer:WaitForChild("PlayerGui")

------------------------------------------------------------------------
-- 1. CONFIGURACIÓN Y LISTAS NEGRAS ESTRICTAS
------------------------------------------------------------------------
local CONFIG = {
    GuiIdentifier = "CustomVisualESP_Container",

    -- Palabras clave que debe tener el huevo
    Keywords = {"egg", "huevo"},

    -- EXCLUSIONES EXPLÍCITAS: Si el objeto o su modelo contiene alguna de estas, SE IGNORA
    Blacklist = {
        -- Máquinas y elementos del mapa que NO son huevos recolectables
        "treadmill", "caminadora", "cinta",
        "fuse", "fusion", "machine", "maquina",
        
        -- Botones, tiendas, pads y puntos de spawn
        "button", "boton", "pad", "stand", "spawn", "spawner", 
        "point", "punto", "buy", "compra", "shop", "tienda", 
        "display", "altar", "pedestal", "hatch", "zone", "zona",
        "upgrade", "door", "puerta", "portal"
    },

    -- Carpetas de jugadores donde los huevos ya están colocados/reclamados
    BlacklistAncestors = {
        "plot", "plots", "base", "bases", "tycoon", "tycoons", 
        "stand", "stands", "house", "casa", "inventory", "incubator"
    },

    -- Visuales del Huevo
    HighlightColor = Color3.fromRGB(255, 185, 45),     -- Dorado
    HighlightOutline = Color3.fromRGB(255, 255, 255),
    FillTransparency = 0.5,
    OutlineTransparency = 0.15,
    TextSize = 12,
    StudsOffset = Vector3.new(0, 2.5, 0),
    UpdateInterval = 0.1,
}

------------------------------------------------------------------------
-- 2. CONTROL DE INSTANCIAS PREVIAS (Idempotencia)
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
-- 4. FILTRADO ESTRICTO DE HUEVOS
------------------------------------------------------------------------

-- Comprueba si el objeto pertenece a una base o plot de algún jugador
local function isInPlayerBase(instance: Instance): boolean
    local current: Instance? = instance.Parent
    while current and current ~= workspace do
        local parentName = string.lower(current.Name)

        -- Verificar si la carpeta coincide con nombres de bases/plots
        for _, blackName in ipairs(CONFIG.BlacklistAncestors) do
            if string.find(parentName, blackName) then
                return true
            end
        end

        -- Si la estructura tiene dueño asignado (Owner / OwnerValue)
        if current:GetAttribute("Owner") or current:FindFirstChild("Owner") or current:FindFirstChild("OwnerValue") then
            return true
        end

        current = current.Parent
    end
    return false
end

-- Determina si una cadena contiene alguna palabra de la lista negra
local function containsBlacklistedWord(text: string): boolean
    local lower = string.lower(text)
    for _, word in ipairs(CONFIG.Blacklist) do
        if string.find(lower, word) then
            return true
        end
    end
    return false
end

-- Valida que sea única y exclusivamente un huevo libre en el mapa
local function isValidFreeEgg(instance: Instance): (boolean, BasePart?)
    if not (instance:IsA("Model") or instance:IsA("BasePart")) then
        return false, nil
    end

    -- 1. Descartar si pertenece a un personaje
    if instance:FindFirstAncestorWhichIsA("Player") or instance:FindFirstChildOfClass("Humanoid") then
        return false, nil
    end

    -- 2. Descartar si está en la base / plot de un jugador
    if isInPlayerBase(instance) then
        return false, nil
    end

    -- 3. Descartar si el nombre del objeto es una máquina (Treadmill, Fuse), botón, etc.
    if containsBlacklistedWord(instance.Name) then
        return false, nil
    end

    -- 4. Descartar si su padre directo o modelo superior es una máquina
    if instance.Parent and instance.Parent ~= workspace and containsBlacklistedWord(instance.Parent.Name) then
        return false, nil
    end

    -- 5. Debe contener "egg" o "huevo"
    local nameLower = string.lower(instance.Name)
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

    -- 6. Si es un Modelo complejo, comprobar que no sea una estación o máquina con piezas internas
    if instance:IsA("Model") then
        for _, child in ipairs(instance:GetChildren()) do
            if containsBlacklistedWord(child.Name) then
                return false, nil
            end
        end
    end

    -- 7. Obtener la parte física
    local basePart: BasePart? = nil
    if instance:IsA("BasePart") then
        -- Ignorar partes invisibles (triggers/hitboxes)
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
-- 5. VISUALES (HIGHLIGHT + BILLBOARDGUI)
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

    -- Highlight (silueta visible a través de paredes)
    local highlight = Instance.new("Highlight")
    highlight.Name = "ESP_Highlight_" .. targetInstance.Name
    highlight.Adornee = targetInstance
    highlight.FillColor = CONFIG.HighlightColor
    highlight.OutlineColor = CONFIG.HighlightOutline
    highlight.FillTransparency = CONFIG.FillTransparency
    highlight.OutlineTransparency = CONFIG.OutlineTransparency
    highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
    highlight.Parent = espFolder

    -- BillboardGui (nombre y distancia flotante)
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
    label.Text = string.format("🥚 %s\n[-- studs]", targetInstance.Name)
    label.Parent = billboard

    -- Limpieza reactiva si el huevo es tomado o movido a una base
    local ancestryConn: RBXScriptConnection
    ancestryConn = targetInstance.AncestryChanged:Connect(function(_, parent)
        if not parent or isInPlayerBase(targetInstance) then
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
for _, desc in ipairs(workspace:GetDescendants()) do
    evaluateInstance(desc)
end

workspace.DescendantAdded:Connect(function(desc)
    task.wait(0.1)
    evaluateInstance(desc)
end)

workspace.DescendantRemoving:Connect(function(desc)
    if trackedRegistry[desc] then
        removeVisuals(desc)
    end
end)

------------------------------------------------------------------------
-- 7. BUCLE DE DISTANCIAS
------------------------------------------------------------------------
local accumulated = 0

RunService.RenderStepped:Connect(function(dt: number)
    accumulated += dt
    if accumulated < CONFIG.UpdateInterval then return end
    accumulated = 0

    local character = localPlayer.Character
    local rootPart = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?

    for instance, entry in pairs(trackedRegistry) do
        -- Si fue destruido o colocado en base de jugador, removerlo
        if not instance.Parent or not entry.TargetPart.Parent or isInPlayerBase(instance) then
            removeVisuals(instance)
            continue
        end

        if rootPart then
            local dist = (rootPart.Position - entry.TargetPart.Position).Magnitude
            entry.Label.Text = string.format("🥚 %s\n[%.0f studs]", instance.Name, dist)
        end
    end
end)
