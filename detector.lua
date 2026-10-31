
--!strict
--[[
    ========================================================================
    ESP PRECISO PARA HUEVOS DEL MAPA (BASADO EN LA ARQUITECTURA DEL JUEGO)
    ========================================================================
    Estudiado a partir del código y assets internos de "Robar un huevo":
      - Huevos de Campo (Field): Gestionados por AreaEggs / CarryAreaEgg
      - Huevos de Halloween: Gestionados por HalloweenDimensionEgg / CarryHalloweenEgg
      - Exclusiones del juego:
          * PlacedEggPrompt / PlacedEggBillboard (Huevos colocados en bases de jugadores)
          * EggPoint, EggSpotBottom, EggFitBounds, EggSpawn (Puntos de anclaje/spawns)
          * Treadmills y Fuse Machine (Cintas y máquinas de fusión)
          * EggShopPrompt (Tiendas y vitrinas)
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local localPlayer = Players.LocalPlayer
local playerGui = localPlayer:WaitForChild("PlayerGui")

------------------------------------------------------------------------
-- 1. CONFIGURACIÓN DEL SISTEMA
------------------------------------------------------------------------
local CONFIG = {
    GuiIdentifier = "GamePrecise_EggESP",

    -- Colores diferenciados por dimensión
    Colors = {
        Field = Color3.fromRGB(255, 195, 45),       -- Amarillo / Oro brillante
        Halloween = Color3.fromRGB(200, 75, 255),    -- Morado Halloween
        Default = Color3.fromRGB(255, 180, 50),
    },

    StudsOffset = Vector3.new(0, 2.8, 0),
    MaxRenderDistance = 2500,
    UpdateInterval = 0.08,
}

------------------------------------------------------------------------
-- 2. LIMPIEZA PREVENTIVA (Idempotencia)
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
-- 3. ESTADO
------------------------------------------------------------------------
type EggRecord = {
    Instance: Instance,
    TargetPart: BasePart,
    Billboard: BillboardGui,
    Label: TextLabel,
    Highlight: Highlight,
    Category: string,
    AncestryConn: RBXScriptConnection,
}

local trackedRegistry: {[Instance]: EggRecord} = {}

------------------------------------------------------------------------
-- 4. DISCRIMINACIÓN EXACTA BASADA EN EL JUEGO
------------------------------------------------------------------------

-- Determina la parte física donde anclar el ESP
local function getPhysicalPart(instance: Instance): BasePart?
    if instance:IsA("BasePart") then
        return instance
    elseif instance:IsA("Model") then
        return instance.PrimaryPart 
            or instance:FindFirstChild("Eggcore") :: BasePart?
            or instance:FindFirstChild("EggRoot") :: BasePart?
            or instance:FindFirstChildWhichIsA("BasePart")
    end
    return nil
end

-- Determina si un objeto es un HUEVO REAL recolectable/robable
local function isRealStealableEgg(instance: Instance): (boolean, string)
    -- Descartar si pertenece al personaje de un jugador
    if instance:FindFirstAncestorWhichIsA("Player") or instance:FindFirstChildOfClass("Humanoid") then
        return false, ""
    end

    local name = instance.Name
    local nameLower = string.lower(name)

    -- A) EXCLUSIÓN DE PUNTOS DE ANCLAJE, SPAWNS Y BOUNDS
    -- En el juego estos son marcadores invisibles o bases
    if string.find(nameLower, "eggpoint") 
        or string.find(nameLower, "eggspot") 
        or string.find(nameLower, "eggfitbounds") 
        or string.find(nameLower, "eggspawn") 
        or string.find(nameLower, "eggmouth")
        or string.find(nameLower, "eggpoof")
        or string.find(nameLower, "egglanding") then
        return false, ""
    end

    -- B) EXCLUSIÓN DE MÁQUINAS Y TIENDAS
    -- Treadmills, Fuse Machines y Egg Shops
    if string.find(nameLower, "treadmill") 
        or string.find(nameLower, "fuse") 
        or string.find(nameLower, "shop") 
        or string.find(nameLower, "machine") then
        return false, ""
    end

    -- Si sus ancestros inmediatos son una máquina o la tienda
    local parent = instance.Parent
    if parent and parent ~= workspace then
        local parentName = string.lower(parent.Name)
        if string.find(parentName, "treadmill") 
            or string.find(parentName, "fuse") 
            or string.find(parentName, "shop") 
            or string.find(parentName, "eggholders") then
            return false, ""
        end
    end

    -- C) EXCLUSIÓN DE HUEVOS YA COLOCADOS EN BASES DE JUGADORES
    -- En el código del juego, los huevos colocados usan "PlacedEggPrompt" o "PlacedEggBillboard"
    if instance:FindFirstChild("PlacedEggPrompt", true) 
        or instance:FindFirstChild("PlacedEggBillboard", true)
        or instance:FindFirstChild("EggHolders") then
        return false, ""
    end

    -- Si está dentro de la base / plot de un jugador
    local ancestor: Instance? = instance.Parent
    while ancestor and ancestor ~= workspace do
        local ancName = string.lower(ancestor.Name)
        if string.find(ancName, "base") 
            or string.find(ancName, "plot") 
            or string.find(ancName, "tycoon") 
            or ancestor:GetAttribute("Owner") 
            or ancestor:FindFirstChild("Owner") then
            return false, ""
        end
        ancestor = ancestor.Parent
    end

    -- D) VERIFICACIÓN DE HUEVOS LIBRES
    -- 1. Método más seguro: ProximityPrompt de robo nativo del juego
    local prompt = instance:FindFirstChildWhichIsA("ProximityPrompt", true)
    if prompt then
        local pName = prompt.Name
        if pName == "CarryAreaEgg" or pName == "StealEgg" then
            return true, "Field"
        elseif pName == "CarryHalloweenEgg" or pName == "HalloweenEggPrompt" then
            return true, "Halloween"
        elseif string.find(string.lower(pName), "egg") and not string.find(string.lower(pName), "placed") then
            return true, "Default"
        end
    end

    -- 2. Detección por carpetas de origen del juego (AreaEggs, Nests, HalloweenDimensionEgg)
    if instance:IsDescendantOf(workspace) then
        local current: Instance? = instance.Parent
        while current and current ~= workspace do
            local folderName = current.Name
            if folderName == "AreaEggs" or string.find(folderName, "Nests") then
                return true, "Field"
            elseif string.find(folderName, "Halloween") and string.find(folderName, "Egg") then
                return true, "Halloween"
            end
            current = current.Parent
        end
    end

    -- 3. Modelos nombrados específicamente como Egg en el mundo
    if (string.find(nameLower, "egg") or string.find(nameLower, "huevo")) and (instance:IsA("Model") or instance:IsA("BasePart")) then
        -- Solo si no es una parte transparente suelta de efectos
        if instance:IsA("BasePart") and instance.Transparency >= 0.9 then
            return false, ""
        end
        if string.find(nameLower, "halloween") then
            return true, "Halloween"
        end
        return true, "Field"
    end

    return false, ""
end

------------------------------------------------------------------------
-- 5. CREACIÓN Y GESTIÓN DE ELEMENTOS VISUALES
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

local function createVisuals(targetInstance: Instance, targetPart: BasePart, category: string)
    if trackedRegistry[targetInstance] then return end

    local color = CONFIG.Colors[category] or CONFIG.Colors.Default
    local categoryPrefix = (category == "Halloween") and "🎃 " or "🥚 "

    -- Highlight (silueta 3D a través de muros)
    local highlight = Instance.new("Highlight")
    highlight.Name = "ESP_Highlight_" .. targetInstance.Name
    highlight.Adornee = targetInstance
    highlight.FillColor = color
    highlight.OutlineColor = Color3.fromRGB(255, 255, 255)
    highlight.FillTransparency = 0.5
    highlight.OutlineTransparency = 0.15
    highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
    highlight.Parent = espFolder

    -- BillboardGui (indicador flotante de distancia)
    local billboard = Instance.new("BillboardGui")
    billboard.Name = "ESP_Billboard_" .. targetInstance.Name
    billboard.Adornee = targetPart
    billboard.Size = UDim2.new(0, 140, 0, 36)
    billboard.StudsOffset = CONFIG.StudsOffset
    billboard.AlwaysOnTop = true
    billboard.MaxDistance = CONFIG.MaxRenderDistance
    billboard.Parent = espFolder

    local label = Instance.new("TextLabel")
    label.Size = UDim2.new(1, 0, 1, 0)
    label.BackgroundTransparency = 1
    label.Font = Enum.Font.GothamBold
    label.TextSize = 12
    label.TextColor3 = color
    label.TextStrokeTransparency = 0.2
    label.TextStrokeColor3 = Color3.fromRGB(15, 15, 20)
    label.Text = string.format("%s%s\n[-- studs]", categoryPrefix, targetInstance.Name)
    label.Parent = billboard

    -- Limpieza reactiva si el huevo es recolectado o colocado en base
    local ancestryConn: RBXScriptConnection
    ancestryConn = targetInstance.AncestryChanged:Connect(function(_, parent)
        if not parent or not targetInstance:IsDescendantOf(workspace) then
            removeVisuals(targetInstance)
        else
            -- Si ahora tiene un PlacedEggPrompt, significa que un jugador lo llevó a su base
            if targetInstance:FindFirstChild("PlacedEggPrompt", true) then
                removeVisuals(targetInstance)
            end
        end
    end)

    trackedRegistry[targetInstance] = {
        Instance = targetInstance,
        TargetPart = targetPart,
        Billboard = billboard,
        Label = label,
        Highlight = highlight,
        Category = category,
        AncestryConn = ancestryConn,
    }
end

local function evaluateInstance(instance: Instance)
    local isEgg, category = isRealStealableEgg(instance)
    if isEgg then
        local targetPart = getPhysicalPart(instance)
        if targetPart then
            createVisuals(instance, targetPart, category)
        end
    end
end

------------------------------------------------------------------------
-- 6. ESCANEO Y DETECCIÓN EN TIEMPO REAL
------------------------------------------------------------------------

-- Escaneo de instancias existentes
for _, desc in ipairs(workspace:GetDescendants()) do
    evaluateInstance(desc)
end

-- Cuando un nuevo huevo aparece en el mapa (Ciclo de reset o spawn)
workspace.DescendantAdded:Connect(function(desc)
    task.wait(0.08)
    evaluateInstance(desc)
end)

-- Cuando un huevo es destruido o robado
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
        -- Si fue destruido o recogido
        if not instance.Parent or not entry.TargetPart.Parent then
            removeVisuals(instance)
            continue
        end

        local prefix = (entry.Category == "Halloween") and "🎃 " or "🥚 "

        if rootPart then
            local dist = (rootPart.Position - entry.TargetPart.Position).Magnitude
            entry.Label.Text = string.format("%s%s\n[%.0f studs]", prefix, instance.Name, dist)
        else
            entry.Label.Text = string.format("%s%s\n[--]", prefix, instance.Name)
        end
    end
end)

print("[ESP] Sistema calibrado con la arquitectura interna de Robar un Huevo.")

