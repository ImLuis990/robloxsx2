--!strict
--[[
    ========================================================================
    SISTEMA MODULAR DE ESP Y RASTREO VISUAL DE OBJETOS EN TIEMPO REAL
    ========================================================================
    Entorno: Roblox Studio (LocalScript)
    Ubicación recomendada: StarterPlayer -> StarterPlayerScripts (o StarterGui)
    
    Funcionalidades:
      1. Escaneo dinámico y continuo en Workspace (coincidencia de nombres).
      2. Generación programática de Highlight y BillboardGui sobre el objetivo.
      3. Cálculo optimizado de distancias en studs mediante RunService.RenderStepped.
      4. Limpieza automática al destruirse objetos y eliminación de instancias previas.
]]

-- Servicios del motor
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local localPlayer = Players.LocalPlayer
local playerGui = localPlayer:WaitForChild("PlayerGui")

------------------------------------------------------------------------
-- 1. CONFIGURACIÓN DEL SISTEMA
------------------------------------------------------------------------
local CONFIG = {
    -- Identificador único para evitar duplicación del GUI en re-ejecuciones
    GuiIdentifier = "CustomVisualESP_Container",

    -- Palabras clave a rastrear (en minúsculas)
    Keywords = {"egg", "huevo"},

    -- Configuración estética del Highlight (silueta 3D)
    HighlightColor = Color3.fromRGB(255, 185, 45),     -- Tono dorado / ámbar
    HighlightOutline = Color3.fromRGB(255, 255, 255),   -- Contorno blanco
    FillTransparency = 0.5,                             -- Opacidad del relleno interior
    OutlineTransparency = 0.1,                          -- Opacidad de los bordes externos

    -- Configuración estética del BillboardGui (texto flotante)
    LabelTextColor = Color3.fromRGB(255, 220, 100),
    LabelStrokeColor = Color3.fromRGB(15, 15, 20),
    TextSize = 12,
    StudsOffset = Vector3.new(0, 2.8, 0),               -- Elevación sobre el objeto

    -- Intervalo de refresco para el cálculo de distancias (en segundos)
    UpdateInterval = 0.1,
}

------------------------------------------------------------------------
-- 2. CONTROL DE INSTANCIAS PREVIAS (Idempotencia)
------------------------------------------------------------------------
-- Busca y destruye cualquier contenedor previo para evitar duplicados en memoria
local function cleanupPreviousInstances()
    local existingContainer = playerGui:FindFirstChild(CONFIG.GuiIdentifier)
    if existingContainer then
        existingContainer:Destroy()
    end
end

cleanupPreviousInstances()

-- Contenedor principal para almacenar todos los BillboardGuis y Highlights
local espFolder = Instance.new("Folder")
espFolder.Name = CONFIG.GuiIdentifier
espFolder.Parent = playerGui

------------------------------------------------------------------------
-- 3. ESTRUCTURAS DE DATOS Y ESTADO
------------------------------------------------------------------------
type TrackedEntry = {
    Instance: Instance,
    TargetPart: BasePart,
    Billboard: BillboardGui,
    Label: TextLabel,
    Highlight: Highlight,
    AncestryConn: RBXScriptConnection,
}

-- Registro de objetos actualmente procesados
local trackedRegistry: {[Instance]: TrackedEntry} = {}

------------------------------------------------------------------------
-- 4. VALIDACIÓN Y FILTRADO DE OBJETOS
------------------------------------------------------------------------

-- Extrae la parte física (BasePart) para anclar los elementos visuales
local function getPhysicalPart(instance: Instance): BasePart?
    if instance:IsA("BasePart") then
        return instance
    elseif instance:IsA("Model") then
        return instance.PrimaryPart or instance:FindFirstChildWhichIsA("BasePart")
    end
    return nil
end

-- Determina si el objeto califica según las palabras clave configuradas
local function matchesFilter(instance: Instance): boolean
    -- Ignorar personajes de jugadores
    if instance:FindFirstAncestorWhichIsA("Player") or instance:FindFirstChildOfClass("Humanoid") then
        return false
    end

    local nameLower = string.lower(instance.Name)
    for _, kw in ipairs(CONFIG.Keywords) do
        if string.find(nameLower, kw) then
            return true
        end
    end
    return false
end

------------------------------------------------------------------------
-- 5. CREACIÓN Y DESTRUCCIÓN DE ELEMENTOS VISUALES
------------------------------------------------------------------------

-- Elimina los elementos visuales asociados a un objeto y libera conexiones
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

-- Genera el Highlight y BillboardGui sobre el objetivo
local function createVisuals(targetInstance: Instance, targetPart: BasePart)
    if trackedRegistry[targetInstance] then return end

    -- A) Crear Highlight (silueta visible a través de paredes)
    local highlight = Instance.new("Highlight")
    highlight.Name = "ESP_Highlight_" .. targetInstance.Name
    highlight.Adornee = targetInstance
    highlight.FillColor = CONFIG.HighlightColor
    highlight.OutlineColor = CONFIG.HighlightOutline
    highlight.FillTransparency = CONFIG.FillTransparency
    highlight.OutlineTransparency = CONFIG.OutlineTransparency
    highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
    highlight.Parent = espFolder

    -- B) Crear BillboardGui (indicador de texto flotante 3D)
    local billboard = Instance.new("BillboardGui")
    billboard.Name = "ESP_Billboard_" .. targetInstance.Name
    billboard.Adornee = targetPart
    billboard.Size = UDim2.new(0, 140, 0, 36)
    billboard.StudsOffset = CONFIG.StudsOffset
    billboard.AlwaysOnTop = true
    billboard.MaxDistance = 1500 -- Distancia máxima de visibilidad en studs
    billboard.Parent = espFolder

    local label = Instance.new("TextLabel")
    label.Size = UDim2.new(1, 0, 1, 0)
    label.BackgroundTransparency = 1
    label.Font = Enum.Font.GothamBold
    label.TextSize = CONFIG.TextSize
    label.TextColor3 = CONFIG.LabelTextColor
    label.TextStrokeTransparency = 0.2
    label.TextStrokeColor3 = CONFIG.LabelStrokeColor
    label.Text = string.format("🥚 %s\n[-- studs]", targetInstance.Name)
    label.Parent = billboard

    -- C) Listener de eliminación: limpia visuales si el objeto sale de la jerarquía
    local ancestryConn: RBXScriptConnection
    ancestryConn = targetInstance.AncestryChanged:Connect(function(_, parent)
        if not parent then
            removeVisuals(targetInstance)
        end
    end)

    -- Guardar en el registro
    trackedRegistry[targetInstance] = {
        Instance = targetInstance,
        TargetPart = targetPart,
        Billboard = billboard,
        Label = label,
        Highlight = highlight,
        AncestryConn = ancestryConn,
    }
end

-- Inspecciona una instancia para registrarla si cumple los criterios
local function evaluateInstance(instance: Instance)
    if matchesFilter(instance) then
        local physicalPart = getPhysicalPart(instance)
        if physicalPart then
            createVisuals(instance, physicalPart)
        end
    end
end

------------------------------------------------------------------------
-- 6. ESCANEO INICIAL Y DETECCIÓN EN TIEMPO REAL
------------------------------------------------------------------------

-- Escaneo de elementos ya existentes en el Workspace
for _, descendant in ipairs(workspace:GetDescendants()) do
    evaluateInstance(descendant)
end

-- Detección reactiva: nuevos objetos que aparecen en el Workspace
workspace.DescendantAdded:Connect(function(descendant)
    -- Breve retardo para permitir que carguen las partes hijas si es un modelo compuesto
    task.wait(0.05)
    evaluateInstance(descendant)
end)

-- Limpieza reactiva: objetos que son removidos del Workspace
workspace.DescendantRemoving:Connect(function(descendant)
    if trackedRegistry[descendant] then
        removeVisuals(descendant)
    end
end)

------------------------------------------------------------------------
-- 7. BUCLE DE ACTUALIZACIÓN CON CONTROL DE RENDIMIENTO (THROTTLING)
------------------------------------------------------------------------
local accumulatedTime = 0

RunService.RenderStepped:Connect(function(deltaTime: number)
    accumulatedTime += deltaTime

    -- Limitar ejecución al intervalo establecido para preservar recursos
    if accumulatedTime < CONFIG.UpdateInterval then
        return
    end
    accumulatedTime = 0

    -- Obtener la posición del jugador local
    local character = localPlayer.Character
    local rootPart = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?

    for instance, entry in pairs(trackedRegistry) do
        -- Validación de existencia en el árbol de instancias
        if not instance.Parent or not entry.TargetPart.Parent then
            removeVisuals(instance)
            continue
        end

        -- Actualizar texto con la distancia calculada en studs
        if rootPart then
            local distance = (rootPart.Position - entry.TargetPart.Position).Magnitude
            entry.Label.Text = string.format("🥚 %s\n[%.0f studs]", instance.Name, distance)
        else
            entry.Label.Text = string.format("🥚 %s\n[--]", instance.Name)
        end
    end
end)
