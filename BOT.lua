-- ═══════════════════════════════════════════════════════════
-- LEGENDS BATTLEGROUNDS - SMART COMBO BOT v3.0
-- Para Arceus X - Artes Marciales Edition
-- ═══════════════════════════════════════════════════════════

local Players = game:GetService("Players")
local VirtualInputManager = game:GetService("VirtualInputManager")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local player = Players.LocalPlayer
local camera = workspace.CurrentCamera

-- ═══════════════════════════════════════════════════════════
-- CONFIGURACIÓN DE COORDENADAS (Motorola Edge 30)
-- ═══════════════════════════════════════════════════════════

local UI = {
    ATTACK = {X = 2100, Y = 550},
    DASH = {X = 2100, Y = 750},
    BLOCK = {X = 2100, Y = 300},
    JUMP = {X = 2100, Y = 950},
    
    -- Habilidades Artes Marciales
    SKILL_1 = {X = 700, Y = 1050},   -- Carrera del Dragón
    SKILL_2 = {X = 950, Y = 1050},   -- Palma de Tigre
    SKILL_3 = {X = 1200, Y = 1050},  -- Combo Pantera
    SKILL_4 = {X = 1450, Y = 1050},  -- Contador de tres patadas
    
    JOYSTICK = {X = 180, Y = 900}
}

-- ═══════════════════════════════════════════════════════════
-- VARIABLES DEL BOT
-- ═══════════════════════════════════════════════════════════

local BotState = {
    Enabled = false,
    Target = nil,
    Action = "Esperando...",
    NextAction = "Buscar enemigo",
    Distance = 0,
    Health = 100,
    ComboCount = 0,
    IsAttacking = false,
    IsDodging = false,
    LastDash = 0,
    LastSideDash = 0,
    KillCount = 0
}

-- ═══════════════════════════════════════════════════════════
-- FUNCIONES DE INPUT
-- ═══════════════════════════════════════════════════════════

local function Tap(x, y, duration)
    duration = duration or 0.05
    VirtualInputManager:SendTouchEvent(x, y, 0, true)
    wait(duration)
    VirtualInputManager:SendTouchEvent(x, y, 0, false)
    wait(0.05)
end

local function Hold(x, y, duration)
    VirtualInputManager:SendTouchEvent(x, y, 0, true)
    wait(duration)
    VirtualInputManager:SendTouchEvent(x, y, 0, false)
end

local function Attack(count)
    BotState.IsAttacking = true
    BotState.Action = "Atacando (M1 x" .. count .. ")"
    for i = 1, count do
        if not BotState.Enabled then break end
        Tap(UI.ATTACK.X, UI.ATTACK.Y, 0.05)
        wait(0.12)
    end
    BotState.IsAttacking = false
end

local function Dash()
    local now = tick()
    if now - BotState.LastDash < 3 then return end
    BotState.LastDash = now
    BotState.Action = "Dash!"
    Tap(UI.DASH.X, UI.DASH.Y, 0.1)
    wait(0.2)
end

local function SideDash(direction)
    local now = tick()
    if now - BotState.LastSideDash < 4 then return end
    BotState.LastSideDash = now
    BotState.Action = "Side Dash " .. direction .. "!"
    
    -- Girar cámara 90 grados + dash
    local center = UI.JOYSTICK
    local offset = direction == "left" and {-100, 0} or {100, 0}
    
    -- Simular giro + dash
    VirtualInputManager:SendTouchEvent(center.X, center.Y, 0, true)
    wait(0.05)
    VirtualInputManager:SendTouchEvent(center.X + offset[1], center.Y + offset[2], 0, true)
    wait(0.1)
    Tap(UI.DASH.X, UI.DASH.Y, 0.1)
    wait(0.1)
    VirtualInputManager:SendTouchEvent(center.X, center.Y, 0, false)
    wait(0.2)
end

local function Skill(slot)
    local coord = UI["SKILL_" .. slot]
    if coord then
        BotState.Action = "Habilidad " .. slot
        Tap(coord.X, coord.Y, 0.1)
        wait(0.4)
    end
end

local function MoveToTarget(target)
    if not target or not target:FindFirstChild("HumanoidRootPart") then return end
    
    local myChar = player.Character
    if not myChar or not myChar:FindFirstChild("HumanoidRootPart") then return end
    
    local myPos = myChar.HumanoidRootPart.Position
    local targetPos = target.HumanoidRootPart.Position
    local direction = (targetPos - myPos).Unit
    
    BotState.Action = "Moviendo hacia objetivo"
    
    -- Calcular dirección del joystick
    local center = UI.JOYSTICK
    local moveX = direction.X * 100
    local moveZ = direction.Z * 100
    
    VirtualInputManager:SendTouchEvent(center.X, center.Y, 0, true)
    wait(0.05)
    VirtualInputManager:SendTouchEvent(center.X + moveX, center.Y + moveZ, 0, true)
    wait(0.1)
    VirtualInputManager:SendTouchEvent(center.X, center.Y, 0, false)
end

-- ═══════════════════════════════════════════════════════════
-- SISTEMA DE HIGHLIGHT
-- ═══════════════════════════════════════════════════════════

local HighlightBox = nil
local TargetArrow = nil

local function CreateHighlight()
    -- Caja de selección
    local box = Instance.new("BoxHandleAdornment")
    box.Size = Vector3.new(4, 6, 4)
    box.Color3 = Color3.fromRGB(255, 0, 0)
    box.Transparency = 0.5
    box.ZIndex = 10
    box.AlwaysOnTop = true
    box.Visible = false
    box.Parent = workspace
    
    -- Flecha indicadora
    local arrow = Instance.new("BillboardGui")
    arrow.Size = UDim2.new(0, 100, 0, 100)
    arrow.AlwaysOnTop = true
    arrow.Enabled = false
    
    local arrowLabel = Instance.new("TextLabel")
    arrowLabel.Size = UDim2.new(1, 0, 1, 0)
    arrowLabel.BackgroundTransparency = 1
    arrowLabel.Text = "⬆ TARGET ⬆"
    arrowLabel.TextColor3 = Color3.fromRGB(255, 0, 0)
    arrowLabel.TextStrokeTransparency = 0
    arrowLabel.Font = Enum.Font.GothamBold
    arrowLabel.TextSize = 20
    arrowLabel.Parent = arrow
    
    return box, arrow
end

local function UpdateHighlight(target)
    if not HighlightBox then
        HighlightBox, TargetArrow = CreateHighlight()
    end
    
    if target and target:FindFirstChild("HumanoidRootPart") then
        HighlightBox.Visible = true
        TargetArrow.Enabled = true
        HighlightBox.Adornee = target.HumanoidRootPart
        TargetArrow.Adornee = target.HumanoidRootPart
        
        -- Cambiar color según vida
        local humanoid = target:FindFirstChild("Humanoid")
        if humanoid then
            local healthPercent = humanoid.Health / humanoid.MaxHealth
            if healthPercent > 0.5 then
                HighlightBox.Color3 = Color3.fromRGB(255, 255, 0) -- Amarillo
            elseif healthPercent > 0.25 then
                HighlightBox.Color3 = Color3.fromRGB(255, 150, 0) -- Naranja
            else
                HighlightBox.Color3 = Color3.fromRGB(255, 0, 0) -- Rojo
            end
        end
    else
        HighlightBox.Visible = false
        TargetArrow.Enabled = false
    end
end

-- ═══════════════════════════════════════════════════════════
-- SISTEMA DE EVASIÓN (Side Dash)
-- ═══════════════════════════════════════════════════════════

local function DetectIncomingAttack()
    local myChar = player.Character
    if not myChar then return false end
    
    local myPos = myChar:FindFirstChild("HumanoidRootPart") and myChar.HumanoidRootPart.Position
    if not myPos then return false end
    
    -- Detectar enemigos cercanos atacando
    for _, other in pairs(Players:GetPlayers()) do
        if other ~= player then
            local char = other.Character
            if char and char:FindFirstChild("HumanoidRootPart") then
                local dist = (char.HumanoidRootPart.Position - myPos).Magnitude
                
                -- Si está muy cerca y mirando hacia nosotros, probablemente va a atacar
                if dist < 8 then
                    local theirLook = char.HumanoidRootPart.CFrame.LookVector
                    local toMe = (myPos - char.HumanoidRootPart.Position).Unit
                    local dot = theirLook:Dot(toMe)
                    
                    -- Si nos está mirando (dot > 0.7 = ~45 grados)
                    if dot > 0.7 then
                        -- Verificar si está en animación de ataque
                        local humanoid = char:FindFirstChild("Humanoid")
                        if humanoid then
                            -- Detectar velocidad alta (ataque incoming)
                            local velocity = char.HumanoidRootPart.Velocity.Magnitude
                            if velocity > 20 then
                                return true, dist
                            end
                        end
                    end
                end
            end
        end
    end
    
    return false, 0
end

local function TryDodge()
    if BotState.IsDodging then return end
    
    local incoming, dist = DetectIncomingAttack()
    if incoming and dist < 10 then
        BotState.IsDodging = true
        BotState.Action = "¡ESQUIVANDO ATAQUE!"
        
        -- Decidir dirección de dodge
        local direction = math.random() > 0.5 and "left" or "right"
        SideDash(direction)
        
        -- Después del dodge, contraatacar
        wait(0.3)
        BotState.NextAction = "Contraataque después de dodge"
        BotState.IsDodging = false
        return true
    end
    
    return false
end

-- ═══════════════════════════════════════════════════════════
-- SISTEMA DE TARGETING
-- ═══════════════════════════════════════════════════════════

local function FindTarget()
    local myChar = player.Character
    if not myChar or not myChar:FindFirstChild("HumanoidRootPart") then
        return nil
    end
    
    local myPos = myChar.HumanoidRootPart.Position
    local nearest = nil
    local minDist = 60
    
    for _, other in pairs(Players:GetPlayers()) do
        if other ~= player then
            local char = other.Character
            if char and char:FindFirstChild("HumanoidRootPart") then
                local humanoid = char:FindFirstChild("Humanoid")
                if humanoid and humanoid.Health > 0 then
                    local dist = (char.HumanoidRootPart.Position - myPos).Magnitude
                    if dist < minDist then
                        minDist = dist
                        nearest = char
                    end
                end
            end
        end
    end
    
    return nearest
end

-- ═══════════════════════════════════════════════════════════
-- COMBOS DE ARTES MARCIALES
-- ═══════════════════════════════════════════════════════════

local Combos = {}

function Combos.Basic()
    BotState.NextAction = "Combo Básico: Dragón → M1 → Tigre"
    Skill(1) -- Carrera del Dragón
    wait(0.3)
    Attack(3)
    wait(0.1)
    Skill(2) -- Palma de Tigre
end

function Combos.Panther()
    BotState.NextAction = "Combo Pantera: Pantera → M1 → Downslam"
    Skill(3) -- Combo Pantera
    wait(0.3)
    Attack(3)
    wait(0.1)
    -- Downslam (simulado con salto + ataque)
    Tap(UI.JUMP.X, UI.JUMP.Y, 0.05)
    wait(0.1)
    Tap(UI.ATTACK.X, UI.ATTACK.Y + 50, 0.1)
end

function Combos.Counter()
    BotState.NextAction = "Counter: Esperar ataque → Contador"
    -- Usar contador de tres patadas cuando el enemigo ataque
    Skill(4)
    wait(0.5)
    Attack(2)
end

function Combos.DragonRush()
    BotState.NextAction = "Dragon Rush: Dash → Dragón → M1"
    Dash()
    wait(0.1)
    Skill(1)
    wait(0.3)
    Attack(3)
    Skill(2)
end

function Combos.WallCombo()
    BotState.NextAction = "Wall Combo: Arrinconar → Pantera → M1"
    -- Mover hacia pared (simplificado)
    Skill(3)
    wait(0.3)
    Attack(3)
    Dash()
    Attack(2)
end

function Combos.Finisher()
    BotState.NextAction = "¡FINISHER! Combo final"
    Skill(1)
    wait(0.2)
    Skill(3)
    wait(0.3)
    Attack(4)
    Skill(2)
end

-- ═══════════════════════════════════════════════════════════
-- LOOP PRINCIPAL
-- ═══════════════════════════════════════════════════════════

local function MainLoop()
    while BotState.Enabled do
        -- Intentar esquivar primero
        if TryDodge() then
            wait(0.5)
        end
        
        -- Buscar target
        if not BotState.Target or not BotState.Target:FindFirstChild("Humanoid") or 
           BotState.Target.Humanoid.Health <= 0 then
            
            if BotState.Target then
                -- Matamos al anterior
                BotState.KillCount = BotState.KillCount + 1
                BotState.Action = "¡ENEMIGO ELIMINADO! (" .. BotState.KillCount .. ")"
                BotState.NextAction = "Buscando siguiente objetivo..."
                wait(1)
            end
            
            BotState.Target = FindTarget()
            BotState.ComboCount = 0
        end
        
        if BotState.Target then
            local myChar = player.Character
            if myChar and myChar:FindFirstChild("HumanoidRootPart") then
                local targetPos = BotState.Target.HumanoidRootPart.Position
                local myPos = myChar.HumanoidRootPart.Position
                local dist = (targetPos - myPos).Magnitude
                
                BotState.Distance = dist
                local humanoid = BotState.Target:FindFirstChild("Humanoid")
                if humanoid then
                    BotState.Health = math.floor((humanoid.Health / humanoid.MaxHealth) * 100)
                end
                
                -- Actualizar highlight
                UpdateHighlight(BotState.Target)
                
                -- Decidir acción según distancia
                if dist > 20 then
                    -- Lejos: acercarse
                    BotState.Action = "Acercándose..."
                    MoveToTarget(BotState.Target)
                    if dist > 30 then
                        Dash()
                    end
                    
                elseif dist > 8 then
                    -- Medio: dash para cerrar
                    BotState.Action = "Cerrando distancia"
                    MoveToTarget(BotState.Target)
                    Dash()
                    
                else
                    -- Cerca: atacar
                    if not BotState.IsAttacking and not BotState.IsDodging then
                        -- Seleccionar combo según vida del enemigo
                        if BotState.Health < 30 then
                            Combos.Finisher()
                        elseif BotState.ComboCount % 3 == 0 then
                            Combos.DragonRush()
                        elseif BotState.ComboCount % 3 == 1 then
                            Combos.Panther()
                        else
                            Combos.Basic()
                        end
                        
                        BotState.ComboCount = BotState.ComboCount + 1
                        wait(0.5)
                    end
                end
            end
        else
            BotState.Action = "Buscando enemigo..."
            BotState.NextAction = "Esperando objetivo"
            UpdateHighlight(nil)
        end
        
        wait(0.1)
    end
    
    UpdateHighlight(nil)
end

-- ═══════════════════════════════════════════════════════════
-- GUI CON INFORMACIÓN DETALLADA
-- ═══════════════════════════════════════════════════════════

local ScreenGui = Instance.new("ScreenGui")
ScreenGui.Name = "SmartBot"
ScreenGui.Parent = game.CoreGui

-- Frame principal
local MainFrame = Instance.new("Frame")
MainFrame.Size = UDim2.new(0, 380, 0, 450)
MainFrame.Position = UDim2.new(0, 15, 0.5, -225)
MainFrame.BackgroundColor3 = Color3.fromRGB(20, 20, 30)
MainFrame.BorderSizePixel = 0
MainFrame.Parent = ScreenGui

local Corner = Instance.new("UICorner")
Corner.CornerRadius = UDim.new(0, 20)
Corner.Parent = MainFrame

-- Gradiente
local Gradient = Instance.new("UIGradient")
Gradient.Color = ColorSequence.new({
    ColorSequenceKeypoint.new(0, Color3.fromRGB(40, 40, 60)),
    ColorSequenceKeypoint.new(1, Color3.fromRGB(15, 15, 25))
})
Gradient.Rotation = 45
Gradient.Parent = MainFrame

-- Barra superior
local TopBar = Instance.new("Frame")
TopBar.Size = UDim2.new(1, 0, 0, 6)
TopBar.BackgroundColor3 = Color3.fromRGB(0, 200, 255)
TopBar.BorderSizePixel = 0
TopBar.Parent = MainFrame

local TopGradient = Instance.new("UIGradient")
TopGradient.Color = ColorSequence.new({
    ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 200, 0)),
    ColorSequenceKeypoint.new(1, Color3.fromRGB(255, 100, 0))
})
TopGradient.Parent = TopBar

-- Título
local Title = Instance.new("TextLabel")
Title.Size = UDim2.new(1, 0, 0, 45)
Title.Position = UDim2.new(0, 0, 0, 10)
Title.BackgroundTransparency = 1
Title.Text = "🥋 SMART BOT - ARTES MARCIALES"
Title.TextColor3 = Color3.fromRGB(255, 200, 0)
Title.Font = Enum.Font.GothamBold
Title.TextSize = 22
Title.Parent = MainFrame

-- Botón Toggle
local ToggleBtn = Instance.new("TextButton")
ToggleBtn.Size = UDim2.new(0.9, 0, 0, 55)
ToggleBtn.Position = UDim2.new(0.05, 0, 0, 65)
ToggleBtn.BackgroundColor3 = Color3.fromRGB(0, 200, 100)
ToggleBtn.Text = "▶ INICIAR BOT"
ToggleBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
ToggleBtn.Font = Enum.Font.GothamBold
ToggleBtn.TextSize = 20
ToggleBtn.Parent = MainFrame

local ToggleCorner = Instance.new("UICorner")
ToggleCorner.CornerRadius = UDim.new(0, 12)
ToggleCorner.Parent = ToggleBtn

-- Panel de información
local InfoFrame = Instance.new("Frame")
InfoFrame.Size = UDim2.new(0.9, 0, 0, 240)
InfoFrame.Position = UDim2.new(0.05, 0, 0, 130)
InfoFrame.BackgroundColor3 = Color3.fromRGB(30, 30, 45)
InfoFrame.BorderSizePixel = 0
InfoFrame.Parent = MainFrame

local InfoCorner = Instance.new("UICorner")
InfoCorner.CornerRadius = UDim.new(0, 15)
InfoCorner.Parent = InfoFrame

-- Labels de información
local function CreateInfoLabel(text, yPos, color)
    local label = Instance.new("TextLabel")
    label.Size = UDim2.new(1, -20, 0, 30)
    label.Position = UDim2.new(0, 10, 0, yPos)
    label.BackgroundTransparency = 1
    label.Text = text
    label.TextColor3 = color or Color3.fromRGB(200, 200, 200)
    label.Font = Enum.Font.Gotham
    label.TextSize = 14
    label.TextXAlignment = Enum.TextXAlignment.Left
    label.Parent = InfoFrame
    return label
end

local StatusLabel = CreateInfoLabel("⚡ Estado: Inactivo", 10, Color3.fromRGB(255, 255, 255))
local TargetLabel = CreateInfoLabel("🎯 Target: Ninguno", 45, Color3.fromRGB(255, 100, 100))
local DistLabel = CreateInfoLabel("📏 Distancia: --", 80, Color3.fromRGB(100, 200, 255))
local HealthLabel = CreateInfoLabel("❤️ Vida Enemigo: --", 115, Color3.fromRGB(255, 50, 50))
local ActionLabel = CreateInfoLabel("⚔️ Acción Actual: Esperando...", 150, Color3.fromRGB(255, 200, 0))
local NextLabel = CreateInfoLabel("🔮 Siguiente: --", 185, Color3.fromRGB(150, 255, 150))
local KillsLabel = CreateInfoLabel("💀 Kills: 0", 220, Color3.fromRGB(200, 100, 255))

-- Botón Dodge Manual
local DodgeBtn = Instance.new("TextButton")
DodgeBtn.Size = UDim2.new(0.42, 0, 0, 45)
DodgeBtn.Position = UDim2.new(0.05, 0, 0, 380)
DodgeBtn.BackgroundColor3 = Color3.fromRGB(0, 150, 200)
DodgeBtn.Text = "↔ SIDE DASH"
DodgeBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
DodgeBtn.Font = Enum.Font.GothamBold
DodgeBtn.TextSize = 14
DodgeBtn.Parent = MainFrame

local DodgeCorner = Instance.new("UICorner")
DodgeCorner.CornerRadius = UDim.new(0, 10)
DodgeCorner.Parent = DodgeBtn

-- Botón Counter
local CounterBtn = Instance.new("TextButton")
CounterBtn.Size = UDim2.new(0.42, 0, 0, 45)
CounterBtn.Position = UDim2.new(0.53, 0, 0, 380)
CounterBtn.BackgroundColor3 = Color3.fromRGB(200, 50, 50)
CounterBtn.Text = "🛡️ CONTADOR"
CounterBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
CounterBtn.Font = Enum.Font.GothamBold
CounterBtn.TextSize = 14
CounterBtn.Parent = MainFrame

local CounterCorner = Instance.new("UICorner")
CounterCorner.CornerRadius = UDim.new(0, 10)
CounterCorner.Parent = CounterBtn

-- Botón Cerrar
local CloseBtn = Instance.new("TextButton")
CloseBtn.Size = UDim2.new(0.9, 0, 0, 35)
CloseBtn.Position = UDim2.new(0.05, 0, 0, 430)
CloseBtn.BackgroundColor3 = Color3.fromRGB(80, 80, 80)
CloseBtn.Text = "Cerrar"
CloseBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
CloseBtn.Font = Enum.Font.Gotham
CloseBtn.TextSize = 14
CloseBtn.Parent = MainFrame

-- ═══════════════════════════════════════════════════════════
-- EVENTOS Y ACTUALIZACIÓN
-- ═══════════════════════════════════════════════════════════

ToggleBtn.MouseButton1Click:Co# BOT-LGBG
created by venice ai
