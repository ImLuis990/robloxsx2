-- ============================================================
--  AutoFishing.client.luau
--  Script de pesca automática para la dimensión Halloween
--  Compatible con: StarterPlayer > StarterPlayerScripts
--  Juego: Robar un Huevo (Place ID: 107778070777162)
--  Autor: generado con análisis de script_1.lua
-- ============================================================

-- ╔══════════════════════════════════════════════════════════╗
-- ║  SERVICIOS Y REFERENCIAS                                ║
-- ╚══════════════════════════════════════════════════════════╝
local Players            = game:GetService("Players")
local RunService         = game:GetService("RunService")
local ReplicatedStorage  = game:GetService("ReplicatedStorage")
local UserInputService   = game:GetService("UserInputService")
local TweenService       = game:GetService("TweenService")

local LocalPlayer  = Players.LocalPlayer
local PlayerGui    = LocalPlayer:WaitForChild("PlayerGui")

-- ============================================================
--  CONFIGURACIÓN PRINCIPAL (ajusta estos valores)
-- ============================================================
local CONFIG = {
	-- Delay entre cada ciclo completo de pesca (segundos)
	DelayEntreCiclos = 1.5,

	-- Cuánto tiempo esperar a que pique el pez (segundos)
	TiempoEsperaMaximo = 30,

	-- Velocidad de auto-click durante el minijuego de tensión
	-- (menor número = más rápido)
	DelayAutoClick = 0.05,

	-- Nombre del RemoteEvent de pesca (del código fuente del juego)
	-- v_u_14.Fishing.Hold  → lanzar anzuelo
	-- v_u_14.Fishing.Cancel → cancelar
	-- El namespace "Fishing" está en ReplicatedStorage.Remotes (o similar)
	-- Se detecta automáticamente en tiempo de ejecución
	RemoteNamespace = "Fishing",
}

-- ============================================================
--  ESTADO GLOBAL (permite toggle on/off limpio)
-- ============================================================
local Estado = {
	AutoFishActivo   = false,   -- toggle principal de pesca
	AutoClickActivo  = false,   -- toggle del minijuego de tensión
	FaseActual       = "Idle",  -- Idle / Casting / Waiting / Reeling
	CiclosTotales    = 0,
	HuevosObtenidos  = 0,
	PetsObtenidos    = 0,
	TokensObtenidos  = 0,
}

-- ============================================================
--  DETECCIÓN AUTOMÁTICA DEL REMOTE DE PESCA
--  El juego registra: v3.Fishing = { Hold = remoteEvent("Hold"), ... }
--  Path real: ReplicatedStorage.Remotes.Fishing.Hold
-- ============================================================
local FishingRemotes = nil

local function BuscarRemoteFishing()
	-- Busca el RemoteEvent "Hold" dentro de cualquier carpeta "Fishing"
	local function buscar(padre, profundidad)
		if profundidad > 5 then return nil end
		for _, hijo in ipairs(padre:GetChildren()) do
			if hijo.Name == "Fishing" then
				local hold = hijo:FindFirstChild("Hold")
				if hold and hold:IsA("RemoteEvent") then
					return hijo
				end
			end
			local resultado = buscar(hijo, profundidad + 1)
			if resultado then return resultado end
		end
		return nil
	end

	-- Intenta en ReplicatedStorage primero
	local remotes = buscar(ReplicatedStorage, 0)
	if remotes then
		return remotes
	end

	-- Fallback: busca en workspace
	return buscar(workspace, 0)
end

-- ============================================================
--  DETECCIÓN DEL PEZPEDESTAL (FishPad en la dimensión Halloween)
-- ============================================================
local function BuscarFishPad()
	-- Los pedestales se llaman "FishPad" o "FishPad2" en el mapa
	local candidatos = {}

	local function buscar(padre, profundidad)
		if profundidad > 8 then return end
		for _, hijo in ipairs(padre:GetChildren()) do
			if hijo.Name == "FishPad" or hijo.Name == "FishPad2" then
				table.insert(candidatos, hijo)
			end
			buscar(hijo, profundidad + 1)
		end
	end

	buscar(workspace, 0)
	return candidatos
end

-- ============================================================
--  DETECCIÓN DE HERRAMIENTA DE PESCA (Haunted Rod)
-- ============================================================
local function ObtenerHerramientaPesca()
	local personaje = LocalPlayer.Character
	if not personaje then return nil end

	-- Busca en el personaje (herramienta equipada)
	for _, tool in ipairs(personaje:GetChildren()) do
		if tool:IsA("Tool") then
			local nombre = tool.Name:lower()
			if nombre:find("rod") or nombre:find("fishing") or nombre:find("cana") or nombre:find("haunted") then
				return tool
			end
		end
	end

	-- Busca en la backpack (herramienta guardada)
	local backpack = LocalPlayer:FindFirstChild("Backpack")
	if backpack then
		for _, tool in ipairs(backpack:GetChildren()) do
			if tool:IsA("Tool") then
				local nombre = tool.Name:lower()
				if nombre:find("rod") or nombre:find("fishing") or nombre:find("cana") or nombre:find("haunted") then
					return tool
				end
			end
		end
	end

	return nil
end

-- ============================================================
--  INTERFAZ GRÁFICA (GUI limpia, sin librerías externas)
-- ============================================================
local GUI_ID = "AutoFishingGUI_RobarHuevo"

-- Limpia GUI anterior si existe (evita duplicados al reiniciar)
if PlayerGui:FindFirstChild(GUI_ID) then
	PlayerGui:FindFirstChild(GUI_ID):Destroy()
end

-- Crea la ScreenGui
local ScreenGui = Instance.new("ScreenGui")
ScreenGui.Name = GUI_ID
ScreenGui.ResetOnSpawn = false
ScreenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
ScreenGui.Parent = PlayerGui

-- Panel principal
local PanelPrincipal = Instance.new("Frame")
PanelPrincipal.Name = "Panel"
PanelPrincipal.Size = UDim2.new(0, 280, 0, 320)
PanelPrincipal.Position = UDim2.new(0, 20, 0.5, -160)
PanelPrincipal.BackgroundColor3 = Color3.fromRGB(18, 18, 28)
PanelPrincipal.BorderSizePixel = 0
PanelPrincipal.Active = true
PanelPrincipal.Draggable = true
PanelPrincipal.Parent = ScreenGui

-- Bordes redondeados del panel
local UICornerPanel = Instance.new("UICorner")
UICornerPanel.CornerRadius = UDim.new(0, 12)
UICornerPanel.Parent = PanelPrincipal

-- Borde sutil
local UIStroke = Instance.new("UIStroke")
UIStroke.Color = Color3.fromRGB(80, 120, 200)
UIStroke.Thickness = 1.5
UIStroke.Parent = PanelPrincipal

-- Barra de título
local Titulo = Instance.new("Frame")
Titulo.Name = "Titulo"
Titulo.Size = UDim2.new(1, 0, 0, 40)
Titulo.BackgroundColor3 = Color3.fromRGB(30, 60, 120)
Titulo.BorderSizePixel = 0
Titulo.Parent = PanelPrincipal

local UICornerTitulo = Instance.new("UICorner")
UICornerTitulo.CornerRadius = UDim.new(0, 12)
UICornerTitulo.Parent = Titulo

-- Texto del título
local TextoTitulo = Instance.new("TextLabel")
TextoTitulo.Size = UDim2.new(1, 0, 1, 0)
TextoTitulo.BackgroundTransparency = 1
TextoTitulo.Text = "🎣 Auto Fishing — Halloween"
TextoTitulo.TextColor3 = Color3.fromRGB(120, 200, 255)
TextoTitulo.Font = Enum.Font.GothamBold
TextoTitulo.TextSize = 14
TextoTitulo.Parent = Titulo

-- ── Función auxiliar: crea una fila de estadística ──────────
local function CrearFilaStat(padre, nombre, valorInicial, posY)
	local fila = Instance.new("Frame")
	fila.Size = UDim2.new(1, -20, 0, 24)
	fila.Position = UDim2.new(0, 10, 0, posY)
	fila.BackgroundTransparency = 1
	fila.Parent = padre

	local etiqueta = Instance.new("TextLabel")
	etiqueta.Size = UDim2.new(0.55, 0, 1, 0)
	etiqueta.BackgroundTransparency = 1
	etiqueta.Text = nombre
	etiqueta.TextColor3 = Color3.fromRGB(160, 160, 180)
	etiqueta.Font = Enum.Font.Gotham
	etiqueta.TextSize = 12
	etiqueta.TextXAlignment = Enum.TextXAlignment.Left
	etiqueta.Parent = fila

	local valor = Instance.new("TextLabel")
	valor.Name = "Valor"
	valor.Size = UDim2.new(0.45, 0, 1, 0)
	valor.Position = UDim2.new(0.55, 0, 0, 0)
	valor.BackgroundTransparency = 1
	valor.Text = tostring(valorInicial)
	valor.TextColor3 = Color3.fromRGB(255, 255, 255)
	valor.Font = Enum.Font.GothamBold
	valor.TextSize = 12
	valor.TextXAlignment = Enum.TextXAlignment.Right
	valor.Parent = fila

	return valor
end

-- ── Estadísticas ──────────────────────────────────────────
local AreaStats = Instance.new("Frame")
AreaStats.Size = UDim2.new(1, 0, 0, 140)
AreaStats.Position = UDim2.new(0, 0, 0, 48)
AreaStats.BackgroundTransparency = 1
AreaStats.Parent = PanelPrincipal

local ValorFase    = CrearFilaStat(AreaStats, "Estado:",    "Inactivo",  4)
local ValorCiclos  = CrearFilaStat(AreaStats, "Ciclos:",    "0",        32)
local ValorHuevos  = CrearFilaStat(AreaStats, "Huevos:",    "0",        60)
local ValorPets    = CrearFilaStat(AreaStats, "Pets:",      "0",        88)
local ValorTokens  = CrearFilaStat(AreaStats, "Tokens:",    "0",       116)

-- ── Slider de delay ────────────────────────────────────────
local LabelDelay = Instance.new("TextLabel")
LabelDelay.Size = UDim2.new(1, -20, 0, 18)
LabelDelay.Position = UDim2.new(0, 10, 0, 196)
LabelDelay.BackgroundTransparency = 1
LabelDelay.Text = "Delay entre ciclos: " .. CONFIG.DelayEntreCiclos .. "s"
LabelDelay.TextColor3 = Color3.fromRGB(160, 160, 180)
LabelDelay.Font = Enum.Font.Gotham
LabelDelay.TextSize = 11
LabelDelay.TextXAlignment = Enum.TextXAlignment.Left
LabelDelay.Parent = PanelPrincipal

local SliderFondo = Instance.new("Frame")
SliderFondo.Size = UDim2.new(1, -20, 0, 10)
SliderFondo.Position = UDim2.new(0, 10, 0, 218)
SliderFondo.BackgroundColor3 = Color3.fromRGB(40, 40, 60)
SliderFondo.BorderSizePixel = 0
SliderFondo.Parent = PanelPrincipal
Instance.new("UICorner", SliderFondo).CornerRadius = UDim.new(1, 0)

local SliderRelleno = Instance.new("Frame")
SliderRelleno.Name = "Relleno"
SliderRelleno.Size = UDim2.new(0.3, 0, 1, 0)  -- 30% = 1.5s de rango 0.5-5s
SliderRelleno.BackgroundColor3 = Color3.fromRGB(80, 140, 255)
SliderRelleno.BorderSizePixel = 0
SliderRelleno.Parent = SliderFondo
Instance.new("UICorner", SliderRelleno).CornerRadius = UDim.new(1, 0)

-- Lógica de arrastre del slider
local arrastrando = false
SliderFondo.InputBegan:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
		arrastrando = true
	end
end)
UserInputService.InputEnded:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
		arrastrando = false
	end
end)
UserInputService.InputChanged:Connect(function(input)
	if arrastrando and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
		local posRelativa = math.clamp(
			(input.Position.X - SliderFondo.AbsolutePosition.X) / SliderFondo.AbsoluteSize.X,
			0, 1
		)
		SliderRelleno.Size = UDim2.new(posRelativa, 0, 1, 0)
		-- Mapeo: 0% = 0.5s, 100% = 5s
		CONFIG.DelayEntreCiclos = math.floor((0.5 + posRelativa * 4.5) * 10) / 10
		LabelDelay.Text = "Delay entre ciclos: " .. CONFIG.DelayEntreCiclos .. "s"
	end
end)

-- ── Botones Toggle ─────────────────────────────────────────
local function CrearBoton(padre, texto, color, posY)
	local btn = Instance.new("TextButton")
	btn.Size = UDim2.new(1, -20, 0, 34)
	btn.Position = UDim2.new(0, 10, 0, posY)
	btn.BackgroundColor3 = color
	btn.BorderSizePixel = 0
	btn.Text = texto
	btn.TextColor3 = Color3.fromRGB(255, 255, 255)
	btn.Font = Enum.Font.GothamBold
	btn.TextSize = 13
	btn.Parent = padre
	Instance.new("UICorner", btn).CornerRadius = UDim.new(0, 8)
	return btn
end

local BtnAutoFish  = CrearBoton(PanelPrincipal, "▶ Auto Fish: OFF",  Color3.fromRGB(50, 50, 80),  238)
local BtnAutoClick = CrearBoton(PanelPrincipal, "▶ Auto Click: OFF", Color3.fromRGB(50, 50, 80),  278)

-- ============================================================
--  NOTIFICACIÓN EN PANTALLA
-- ============================================================
local function Notificar(mensaje, color)
	color = color or Color3.fromRGB(80, 200, 120)

	local notif = Instance.new("Frame")
	notif.Size = UDim2.new(0, 260, 0, 36)
	notif.Position = UDim2.new(0.5, -130, 0, 80)
	notif.BackgroundColor3 = Color3.fromRGB(20, 20, 35)
	notif.BorderSizePixel = 0
	notif.ZIndex = 10
	notif.Parent = ScreenGui
	Instance.new("UICorner", notif).CornerRadius = UDim.new(0, 8)

	local borde = Instance.new("UIStroke")
	borde.Color = color
	borde.Thickness = 1.5
	borde.Parent = notif

	local texto = Instance.new("TextLabel")
	texto.Size = UDim2.new(1, -10, 1, 0)
	texto.Position = UDim2.new(0, 10, 0, 0)
	texto.BackgroundTransparency = 1
	texto.Text = mensaje
	texto.TextColor3 = color
	texto.Font = Enum.Font.GothamBold
	texto.TextSize = 12
	texto.TextXAlignment = Enum.TextXAlignment.Left
	texto.ZIndex = 11
	texto.Parent = notif

	-- Animación de entrada y salida
	notif.BackgroundTransparency = 1
	TweenService:Create(notif, TweenInfo.new(0.3), {BackgroundTransparency = 0}):Play()
	task.delay(2.5, function()
		TweenService:Create(notif, TweenInfo.new(0.4), {BackgroundTransparency = 1, Position = UDim2.new(0.5, -130, 0, 50)}):Play()
		task.delay(0.4, function() notif:Destroy() end)
	end)
end

-- ============================================================
--  ACTUALIZACIÓN DEL UI
-- ============================================================
local function ActualizarUI()
	ValorFase.Text   = Estado.FaseActual
	ValorCiclos.Text = tostring(Estado.CiclosTotales)
	ValorHuevos.Text = tostring(Estado.HuevosObtenidos)
	ValorPets.Text   = tostring(Estado.PetsObtenidos)
	ValorTokens.Text = tostring(Estado.TokensObtenidos)

	-- Color de fase
	local coloresFase = {
		Idle       = Color3.fromRGB(150, 150, 150),
		Casting    = Color3.fromRGB(120, 200, 255),
		Waiting    = Color3.fromRGB(255, 200, 50),
		Reeling    = Color3.fromRGB(50, 220, 100),
		Error      = Color3.fromRGB(255, 80, 80),
	}
	ValorFase.TextColor3 = coloresFase[Estado.FaseActual] or Color3.fromRGB(255, 255, 255)
end

-- ============================================================
--  DETECCIÓN DE RECOMPENSA (monitorea el ChatGui o BillboardGui)
--  El juego muestra notificaciones cuando pescas algo
-- ============================================================
local function MonitorearRecompensas()
	-- Escucha cambios en el inventario del jugador
	-- Si aparece un Tool nuevo en la backpack = pescaste algo
	local backpack = LocalPlayer:FindFirstChild("Backpack")
	if not backpack then return end

	local itemsAnteriores = {}
	for _, item in ipairs(backpack:GetChildren()) do
		itemsAnteriores[item] = true
	end

	backpack.ChildAdded:Connect(function(nuevo)
		if itemsAnteriores[nuevo] then return end
		itemsAnteriores[nuevo] = true

		task.wait(0.1) -- Espera a que se asignen los atributos

		local tipo = nuevo:GetAttribute("ItemType") or ""
		local nombre = nuevo.Name

		if tipo == "AssetEgg" or nombre:lower():find("egg") then
			Estado.HuevosObtenidos = Estado.HuevosObtenidos + 1
			Notificar("🥚 ¡Huevo pescado: " .. nombre .. "!", Color3.fromRGB(255, 200, 50))
		elseif tipo == "AssetPet" or nombre:lower():find("fish") or nombre:lower():find("ghost") then
			Estado.PetsObtenidos = Estado.PetsObtenidos + 1
			Notificar("🐟 ¡Pet pescado: " .. nombre .. "!", Color3.fromRGB(120, 255, 120))
		end
		ActualizarUI()
	end)
end

-- ============================================================
--  CICLO PRINCIPAL DE AUTO FISHING
-- ============================================================
local HiloAutoFish = nil

local function IniciarAutoFish()
	-- Busca el Remote de pesca en tiempo de ejecución
	if not FishingRemotes then
		FishingRemotes = BuscarRemoteFishing()
	end

	if not FishingRemotes then
		Notificar("⚠ No se encontró el Remote de pesca.", Color3.fromRGB(255, 80, 80))
		Estado.FaseActual = "Error"
		ActualizarUI()
		return
	end

	local RemoteHold   = FishingRemotes:FindFirstChild("Hold")
	local RemoteCancel = FishingRemotes:FindFirstChild("Cancel")

	if not RemoteHold then
		Notificar("⚠ Remote 'Hold' no encontrado.", Color3.fromRGB(255, 80, 80))
		Estado.FaseActual = "Error"
		ActualizarUI()
		return
	end

	-- Ciclo de pesca
	while Estado.AutoFishActivo do
		pcall(function()
			-- ─── FASE 1: VERIFICAR HERRAMIENTA ───────────────
			local herramienta = ObtenerHerramientaPesca()
			if not herramienta then
				Estado.FaseActual = "Sin caña"
				ActualizarUI()
				task.wait(2)
				return
			end

			-- Equipar herramienta si está en la backpack
			local personaje = LocalPlayer.Character
			if personaje and not personaje:FindFirstChild(herramienta.Name) then
				herramienta:Activate()
				task.wait(0.3)
			end

			-- ─── FASE 2: LANZAR ANZUELO ──────────────────────
			Estado.FaseActual = "Casting"
			ActualizarUI()

			-- Método principal: FireServer al Remote del juego
			pcall(function()
				RemoteHold:FireServer()
			end)

			-- Fallback: activar la herramienta directamente
			pcall(function()
				if herramienta and herramienta.Parent then
					herramienta:Activate()
				end
			end)

			-- ─── FASE 3: ESPERAR A QUE PIQUE ─────────────────
			Estado.FaseActual = "Waiting"
			ActualizarUI()

			local tiempoEspera = 0
			while Estado.AutoFishActivo and tiempoEspera < CONFIG.TiempoEsperaMaximo do
				task.wait(0.1)
				tiempoEspera = tiempoEspera + 0.1

				-- Detecta si el juego entró en fase "Reeling"
				-- (la barra de tensión aparece en pantalla)
				-- El auto-click se encarga de eso por separado
			end

			-- ─── FASE 4: FINALIZAR CICLO ─────────────────────
			Estado.FaseActual = "Idle"
			Estado.CiclosTotales = Estado.CiclosTotales + 1
			ActualizarUI()

			task.wait(CONFIG.DelayEntreCiclos)
		end)

		-- Protección: si ocurre un error grave, pausa antes de reintentar
		if not Estado.AutoFishActivo then break end
		task.wait(0.1)
	end

	Estado.FaseActual = "Idle"
	ActualizarUI()
end

-- ============================================================
--  CICLO DE AUTO-CLICK (minijuego de tensión "Reeling")
--  El juego usa v_u_185(sesión) que suma Fill con cada click
--  Detectamos el momento Reeling buscando la barra de tensión en UI
-- ============================================================
local HiloAutoClick = nil

local function IniciarAutoClick()
	while Estado.AutoClickActivo do
		pcall(function()
			-- Busca la barra de tensión (ReelBar) en el PlayerGui del juego
			-- El juego muestra una UI durante la fase "Reeling"
			local reelUI = nil

			-- Busca en todos los ScreenGui del jugador
			for _, gui in ipairs(PlayerGui:GetChildren()) do
				if gui:IsA("ScreenGui") and gui.Name ~= GUI_ID then
					-- Busca elementos que indiquen la fase de tensión
					local barra = gui:FindFirstChild("ReelBar", true)
						or gui:FindFirstChild("FishBar", true)
						or gui:FindFirstChild("TensionBar", true)
						or gui:FindFirstChild("ClickButton", true)
						or gui:FindFirstChild("ReelingFrame", true)

					if barra and barra.Visible then
						reelUI = barra
						break
					end
				end
			end

			-- Si detectamos la barra de tensión → simular click
			if reelUI then
				Estado.FaseActual = "Reeling"
				ActualizarUI()

				-- Simula input en la barra (compatible con móvil y PC)
				reelUI:SimulateClick() -- para TextButtons/ImageButtons

			else
				-- Método alternativo: simula tecla de click global
				-- (funciona mientras el personaje tenga la herramienta equipada)
				local herramienta = ObtenerHerramientaPesca()
				if herramienta and herramienta.Parent == LocalPlayer.Character then
					pcall(function()
						herramienta:Activate()
					end)
				end
			end
		end)

		task.wait(CONFIG.DelayAutoClick)
	end
end

-- ============================================================
--  LÓGICA DE LOS BOTONES
-- ============================================================
BtnAutoFish.MouseButton1Click:Connect(function()
	Estado.AutoFishActivo = not Estado.AutoFishActivo

	if Estado.AutoFishActivo then
		BtnAutoFish.Text = "⏹ Auto Fish: ON"
		BtnAutoFish.BackgroundColor3 = Color3.fromRGB(30, 100, 50)
		Notificar("✅ Auto Fish activado", Color3.fromRGB(80, 200, 120))
		MonitorearRecompensas()
		HiloAutoFish = task.spawn(IniciarAutoFish)
	else
		BtnAutoFish.Text = "▶ Auto Fish: OFF"
		BtnAutoFish.BackgroundColor3 = Color3.fromRGB(50, 50, 80)
		Notificar("⏹ Auto Fish detenido", Color3.fromRGB(200, 100, 50))
		Estado.FaseActual = "Idle"
		ActualizarUI()
	end
end)

BtnAutoClick.MouseButton1Click:Connect(function()
	Estado.AutoClickActivo = not Estado.AutoClickActivo

	if Estado.AutoClickActivo then
		BtnAutoClick.Text = "⏹ Auto Click: ON"
		BtnAutoClick.BackgroundColor3 = Color3.fromRGB(30, 80, 100)
		Notificar("✅ Auto Click activado", Color3.fromRGB(80, 180, 255))
		HiloAutoClick = task.spawn(IniciarAutoClick)
	else
		BtnAutoClick.Text = "▶ Auto Click: OFF"
		BtnAutoClick.BackgroundColor3 = Color3.fromRGB(50, 50, 80)
		Notificar("⏹ Auto Click detenido", Color3.fromRGB(200, 100, 50))
	end
end)

-- ============================================================
--  INICIALIZACIÓN
-- ============================================================
Notificar("🎣 Auto Fishing cargado", Color3.fromRGB(120, 200, 255))
ActualizarUI()

-- Pre-busca el Remote al iniciar (en background)
task.spawn(function()
	task.wait(2) -- Espera a que el juego cargue
	FishingRemotes = BuscarRemoteFishing()
	if FishingRemotes then
		Notificar("✅ Remote de pesca detectado", Color3.fromRGB(80, 200, 120))
	else
		Notificar("⚠ Remote no detectado aún — se buscará al activar", Color3.fromRGB(255, 180, 50))
	end
end)

-- ============================================================
--  LIMPIEZA AL SALIR (evita fugas de memoria)
-- ============================================================
game:GetService("Players").PlayerRemoving:Connect(function(jugador)
	if jugador == LocalPlayer then
		Estado.AutoFishActivo  = false
		Estado.AutoClickActivo = false
	end
end)
