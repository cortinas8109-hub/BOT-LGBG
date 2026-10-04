--[[
  LEGENDS BATTLEGROUNDS - SMART BOT v6.0
  Arceus X (Android) - Artes Marciales - Motorola Edge 30

  - Detecta solo como mandar toques y mide/calibra tus botones
  - Movimiento propio (sin joystick) y camara fija en el enemigo
  - Combos con cooldowns, castigo despues de esquivar
  - Defensa: esquiva / bloquea / contador segun la animacion del enemigo
  - Aprende que animaciones enemigas te pegan fuerte y las guarda
  - Retirada si te bajan mucha vida o te rodean
  - En pantalla: highlight, cartel, toques marcados y log de acciones
]]

-- ═════════ SERVICIOS ═════════
local Players = game:GetService("Players")
local VIM = game:GetService("VirtualInputManager")
local RunService = game:GetService("RunService")
local GuiService = game:GetService("GuiService")
local HttpService = game:GetService("HttpService")
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")
local player = Players.LocalPlayer
local function cam() return workspace.CurrentCamera end

-- ═════════ AJUSTES (puedes editarlos) ═════════
local CFG = {
    SkillCooldown = {3, 4, 5, 7}, -- segundos de cada habilidad (1 a 4)
    AttackRange = 6.5,            -- distancia para empezar a pegar
    ChaseRange = 90,              -- distancia maxima para buscar enemigos
    M1Interval = 0.3,             -- segundos entre golpes M1
    DodgeCooldown = 2.2,          -- cooldown del dash
    AutoDodge = true,
    AutoBlock = true,
    AutoCounter = true,
    LockCam = true,               -- camara fija en el enemigo mientras el bot esta activo
    SkillKeys = false,            -- true = usar teclas 1-4 en vez de tocar los botones
    SkipTeammates = false,        -- true = ignorar jugadores de tu mismo equipo
    RetreatHP = 35,               -- % de vida para retirarse
    RecoverHP = 55,               -- % de vida para volver a pelear
    BurstPct = 40,                -- % de vida perdida en 2 s = modo panico
    CrowdLimit = 3,               -- enemigos cerca (25 studs) para retirarse
    OffsetY = 0,                  -- ajuste manual si los toques caen arriba/abajo
}

-- ═════════ ESTADO ═════════
local S = {
    Enabled = false, Alive = true, Run = 0, Lock = 0, Probing = false,
    Target = nil, TargetBlocking = false, TargetFlash = 0,
    State = "LIBRE", Action = "Esperando...", Kind = "idle", Next = "--",
    Dist = 0, THP = 100, MyHP = 100, Kills = 0,
    ComboN = 0, ComboToken = 0,
    LastDash = 0, LastBlock = 0, LastReact = 0, PunishUntil = 0, LastPick = 0,
    MoveVec = nil, MoveExpire = 0,
    Panic = 0, Retreating = false, RetreatStart = 0,
    StuckT = 0, StuckPos = Vector3.zero,
    LastAttacker = nil, LastAttackerT = 0,
    Log = {}, Hits = {}, Recent = {},
}
local lastSkill = {0, 0, 0, 0}
local SKILL_NAMES = {"Dragon", "Tigre", "Pantera", "Contador"}

-- ═════════ BOTONES Y GUARDADO ═════════
local FILE = "LGBG_bot_v6.json"
local BASE = Vector2.new(2400, 1080)
local DEFAULT = {
    ATTACK = {2100, 550}, DASH = {2100, 750}, BLOCK = {2100, 300}, JUMP = {2100, 950},
    SKILL_1 = {700, 1050}, SKILL_2 = {950, 1050}, SKILL_3 = {1200, 1050}, SKILL_4 = {1450, 1050},
}
local BTN_ORDER = {"ATTACK", "DASH", "BLOCK", "JUMP", "SKILL_1", "SKILL_2", "SKILL_3", "SKILL_4"}
local BTN_NAMES = {
    ATTACK = "M1 (ataque)", DASH = "Dash", BLOCK = "Bloqueo", JUMP = "Salto",
    SKILL_1 = "Habilidad 1", SKILL_2 = "Habilidad 2", SKILL_3 = "Habilidad 3", SKILL_4 = "Habilidad 4",
}
local SHORT = {
    ATTACK = "M1", DASH = "DASH", BLOCK = "BLOQ", JUMP = "SALTO",
    SKILL_1 = "S1", SKILL_2 = "S2", SKILL_3 = "S3", SKILL_4 = "S4",
}

local Pos, DEFAULTFRAC, AnimDB = {}, {}, {}
local animCount, dirty, calibrated = 0, false, false
for k, v in pairs(DEFAULT) do
    DEFAULTFRAC[k] = Vector2.new(v[1] / BASE.X, v[2] / BASE.Y)
    Pos[k] = DEFAULTFRAC[k]
end

pcall(function()
    if isfile and isfile(FILE) then
        local d = HttpService:JSONDecode(readfile(FILE))
        if d.pos then
            for k, v in pairs(d.pos) do
                if Pos[k] then Pos[k] = Vector2.new(v[1], v[2]); calibrated = true end
            end
        end
        if d.anim then
            for k, v in pairs(d.anim) do AnimDB[k] = v; animCount += 1 end
        end
    end
end)

local function Save()
    pcall(function()
        local p = {}
        for k, v in pairs(Pos) do p[k] = {v.X, v.Y} end
        writefile(FILE, HttpService:JSONEncode({v = 6, pos = p, anim = AnimDB}))
        dirty = false
    end)
end

-- ═════════ PANTALLAS (HUD y panel) ═════════
local function MakeGui(name, order)
    local g = Instance.new("ScreenGui")
    g.Name = name
    g.ResetOnSpawn = false
    g.IgnoreGuiInset = true
    g.DisplayOrder = order
    g.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    local ok = pcall(function() g.Parent = (gethui and gethui()) or game:GetService("CoreGui") end)
    if not ok or not g.Parent then g.Parent = player:WaitForChild("PlayerGui") end
    return g
end
local hud = MakeGui("LGBG_HUD", 100)
local gui = MakeGui("LGBG_Panel", 101)

-- ═════════ UTILIDADES ═════════
local KIND_COLOR = {
    atk = Color3.fromRGB(255, 110, 80),
    move = Color3.fromRGB(255, 215, 70),
    def = Color3.fromRGB(90, 175, 255),
    warn = Color3.fromRGB(255, 70, 70),
    idle = Color3.fromRGB(200, 200, 200),
    ok = Color3.fromRGB(110, 255, 140),
}
local KIND_ICON = {atk = "⚔", move = "🏃", def = "🛡", warn = "⚠", idle = "💤", ok = "✅"}

local function Log(txt)
    local L = S.Log
    L[#L + 1] = txt
    if #L > 4 then table.remove(L, 1) end
end

local function Act(text, kind, quiet)
    if S.Action ~= text then
        S.Action = text
        if not quiet then Log(text) end
    end
    S.Kind = kind or "idle"
end

local function Lock() S.Lock += 1 end
local function Unlock() S.Lock = math.max(0, S.Lock - 1) end

-- espera t segundos; se congela mientras hay una reaccion defensiva (salvo force)
local function Pause(t, force)
    local e = 0
    while e < t do
        task.wait(0.03)
        if force or S.Lock == 0 then e += 0.03 end
        if not S.Enabled and not force then return false end
    end
    return true
end

local function GetChar()
    local c = player.Character
    local hum = c and c:FindFirstChildOfClass("Humanoid")
    local root = c and c:FindFirstChild("HumanoidRootPart")
    if hum and root and hum.Health > 0 then return c, hum, root end
end

local function SetMove(vec, dur)
    S.MoveVec = vec
    S.MoveExpire = tick() + (dur or 0.15)
end

-- marcador en pantalla (toques del bot, botones detectados)
local function Marker(x, y, text, color, dur, size, static)
    local k = math.clamp(cam().ViewportSize.Y / 360, 0.8, 3)
    local sz = (size or 30) * k
    local d = dur or 0.45
    local f = Instance.new("Frame")
    f.AnchorPoint = Vector2.new(0.5, 0.5)
    f.Position = UDim2.fromOffset(x, y)
    f.Size = UDim2.fromOffset(sz, sz)
    f.BackgroundColor3 = color or Color3.fromRGB(255, 220, 0)
    f.BackgroundTransparency = static and 0.55 or 0.35
    f.BorderSizePixel = 0
    f.ZIndex = 5
    f.Parent = hud
    Instance.new("UICorner", f).CornerRadius = UDim.new(1, 0)
    local l = Instance.new("TextLabel")
    l.AnchorPoint = Vector2.new(0.5, 1)
    l.Position = UDim2.fromOffset(x, y - sz * 0.6)
    l.Size = UDim2.fromOffset(110 * k, 14 * k)
    l.BackgroundTransparency = 1
    l.Text = text
    l.TextColor3 = Color3.new(1, 1, 1)
    l.TextStrokeTransparency = 0.2
    l.Font = Enum.Font.GothamBold
    l.TextSize = 12 * k
    l.ZIndex = 6
    l.Parent = hud
    if not static then
        TweenService:Create(f, TweenInfo.new(d), {
            Size = UDim2.fromOffset(sz * 2, sz * 2),
            BackgroundTransparency = 1,
        }):Play()
    end
    Debris:AddItem(f, d + 0.05)
    Debris:AddItem(l, d + 0.05)
end

-- ═════════ ENTRADA (el modo se detecta solo) ═════════
-- A = SendTouchEvent(id, estado, x, y)
-- B = SendTouchEvent(x, y, id, estado)
-- M = SendMouseButtonEvent (plan de respaldo)
local Input = {Mode = nil, OffY = 0, InDelta = Vector2.zero}
local touchId = 100
local function nextId()
    touchId = touchId >= 190 and 100 or touchId + 1
    return touchId
end

local function raw(mode, id, x, y, state) -- state: 0 = presionar, 2 = soltar
    if mode == "A" then
        VIM:SendTouchEvent(id, state, x, y)
    elseif mode == "B" then
        VIM:SendTouchEvent(x, y, id, state)
    elseif mode == "M" then
        VIM:SendMouseButtonEvent(x, y, 0, state == 0, game, 0)
    end
end

local function Tap(name, hold)
    if not Input.Mode then return end
    local p = Pos[name]
    if not p then return end
    local vs = cam().ViewportSize
    local sx, sy = p.X * vs.X, p.Y * vs.Y
    Marker(sx, sy, SHORT[name] or name)
    local id = nextId()
    local x, y = sx, sy + Input.OffY + CFG.OffsetY
    pcall(raw, Input.Mode, id, x, y, 0)
    task.wait(hold or 0.05)
    pcall(raw, Input.Mode, id, x, y, 2)
    task.wait(0.03)
end

local SKILL_KEYS = {Enum.KeyCode.One, Enum.KeyCode.Two, Enum.KeyCode.Three, Enum.KeyCode.Four}
local function Key(code, hold)
    pcall(function() VIM:SendKeyEvent(true, code, false, game) end)
    task.wait(hold or 0.05)
    pcall(function() VIM:SendKeyEvent(false, code, false, game) end)
end

-- ═════════ RAYOS (paredes) ═════════
local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude
local function Blocked(origin, dir, dist)
    local list = {}
    for _, pl in ipairs(Players:GetPlayers()) do
        if pl.Character then list[#list + 1] = pl.Character end
    end
    rayParams.FilterDescendantsInstances = list
    return workspace:Raycast(origin, dir * dist, rayParams) ~= nil
end

-- ═════════ CONTROLES, MOVIMIENTO Y CAMARA ═════════
local controls
pcall(function()
    local ps = player:WaitForChild("PlayerScripts", 3)
    local pm = ps:WaitForChild("PlayerModule", 3)
    controls = require(pm):GetControls()
end)
local function SetControls(on)
    if not controls then return end
    pcall(function()
        if on then controls:Enable() else controls:Disable() end
    end)
end

local camLocked, prevCamType = false, nil

-- se ejecuta DESPUES de los controles de Roblox, asi el joystick no pelea con el bot
local function MoveStep()
    if not S.Enabled then return end
    local _, hum = GetChar()
    if not hum then return end
    if S.MoveVec and tick() < S.MoveExpire then
        hum:Move(S.MoveVec, false)
    else
        hum:Move(Vector3.zero, false)
    end
end

local function CamStep()
    local c = cam()
    if not c then return end
    local _, _, root = GetChar()
    local tr = S.Target and S.Target:FindFirstChild("HumanoidRootPart")
    if S.Enabled and CFG.LockCam and root and tr then
        if not camLocked then
            camLocked = true
            prevCamType = c.CameraType
        end
        c.CameraType = Enum.CameraType.Scriptable
        local flat = (tr.Position - root.Position) * Vector3.new(1, 0, 1)
        local dir = flat.Magnitude > 0.1 and flat.Unit or root.CFrame.LookVector
        local pos = root.Position - dir * 11 + Vector3.new(0, 5.5, 0)
        local goal = CFrame.lookAt(pos, tr.Position + Vector3.new(0, 1.5, 0))
        c.CFrame = c.CFrame:Lerp(goal, 0.35)
    elseif camLocked then
        camLocked = false
        c.CameraType = prevCamType or Enum.CameraType.Custom
    end
end

pcall(function()
    RunService:BindToRenderStep("LGBG_Move", Enum.RenderPriority.Input.Value + 2, MoveStep)
end)
pcall(function()
    RunService:BindToRenderStep("LGBG_Cam", Enum.RenderPriority.Camera.Value + 1, CamStep)
end)

-- ═════════ EFECTOS EN PANTALLA ═════════
local thl = Instance.new("Highlight")
thl.FillTransparency = 0.65
thl.OutlineTransparency = 0
thl.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
thl.Enabled = false
thl.Parent = hud

local function MakeBillboard(w, h)
    local bb = Instance.new("BillboardGui")
    bb.Size = UDim2.fromOffset(w, h)
    bb.StudsOffset = Vector3.new(0, 3.6, 0)
    bb.AlwaysOnTop = true
    bb.Enabled = false
    bb.ResetOnSpawn = false
    bb.Parent = hud
    local l = Instance.new("TextLabel")
    l.Size = UDim2.fromScale(1, 1)
    l.BackgroundColor3 = Color3.new(0, 0, 0)
    l.BackgroundTransparency = 0.5
    l.TextColor3 = Color3.new(1, 1, 1)
    l.Font = Enum.Font.GothamBold
    l.TextSize = 12
    l.TextWrapped = true
    l.Parent = bb
    Instance.new("UICorner", l).CornerRadius = UDim.new(0, 6)
    return bb, l
end
local tbb, tbl = MakeBillboard(150, 40) -- cartel sobre el target
local mbb, mbl = MakeBillboard(150, 24) -- cartel sobre mi personaje

local thrHL, thrExp = {}, {}
local function FlashThreat(ch)
    local now = tick()
    if ch == S.Target then
        S.TargetFlash = now + 0.7
        return
    end
    local h = thrHL[ch]
    if not h then
        h = Instance.new("Highlight")
        h.FillColor = Color3.fromRGB(255, 40, 40)
        h.OutlineColor = Color3.fromRGB(255, 0, 0)
        h.FillTransparency = 0.5
        h.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
        h.Adornee = ch
        h.Parent = hud
        thrHL[ch] = h
    end
    h.Enabled = true
    thrExp[ch] = now + 0.7
end

-- ═════════ SENSORES Y APRENDIZAJE ═════════
local Enemies = {}
local lastHP = nil
local ES = setmetatable({}, {__mode = "k"})
local React -- se define mas abajo

local IGNORE_WORDS = {
    "idle", "walk", "run", "jump", "fall", "climb", "swim", "sit", "emote", "dance",
    "block", "guard", "stun", "hurt", "ragdoll", "knock", "getup", "land", "spawn",
    "pose", "taunt", "dash", "dodge", "roll", "evade", "equip", "death", "victory",
}
local function Ignored(name)
    local low = name:lower()
    for _, w in ipairs(IGNORE_WORDS) do
        if low:find(w, 1, true) then return true end
    end
    return false
end

local function DangerOf(id)
    local r = AnimDB[id]
    if r and r.seen >= 1 and r.hits > 0 then return r.dmg / r.seen end
    return 0
end

local function OnEnemyAttack(ev)
    if ev.dist > 14 then return end
    if not ev.facing and ev.dist > 7 then return end
    local rec = AnimDB[ev.id]
    if not rec and animCount < 400 then
        rec = {n = ev.name, len = ev.len, seen = 0, hits = 0, dmg = 0}
        AnimDB[ev.id] = rec
        animCount += 1
    end
    if rec then
        rec.seen += 1
        dirty = true
    end
    local R = S.Recent
    R[#R + 1] = ev
    if #R > 8 then table.remove(R, 1) end
    S.LastAttacker, S.LastAttackerT = ev.char, ev.t
    FlashThreat(ev.char)
    Log("⚠ " .. ev.char.Name .. ": " .. ev.name)
    if S.Enabled then React(ev) end
end

local function SenseEnemy(pl, root, now)
    local ch = pl.Character
    if not ch then return nil end
    local h = ch:FindFirstChildOfClass("Humanoid")
    local r = ch:FindFirstChild("HumanoidRootPart")
    if not (h and r) or h.Health <= 0 then return nil end
    local off = root.Position - r.Position
    local dist = off.Magnitude
    local e = {
        char = ch, root = r, hum = h, dist = dist,
        hpPct = h.Health / math.max(h.MaxHealth, 1) * 100,
        blocking = false,
        ff = ch:FindFirstChildOfClass("ForceField") ~= nil,
        friend = (pl.Team ~= nil and pl.Team == player.Team),
    }
    if dist > 40 or (CFG.SkipTeammates and e.friend) then
        local st0 = ES[ch]
        if st0 then st0.prev = {} end
        return e
    end

    local st = ES[ch]
    if not st then
        st = {prev = {}, init = false, lastVel = 0}
        ES[ch] = st
    end
    local facing = dist > 0.1 and r.CFrame.LookVector:Dot(off.Unit) > 0.5
    local cur, fired = {}, false
    local an = h:FindFirstChildOfClass("Animator") or h
    local okT, tracks = pcall(function() return an:GetPlayingAnimationTracks() end)
    if okT and tracks then
        for _, tr in ipairs(tracks) do
            cur[tr] = true
            local nm = (tr.Animation and tr.Animation.Name) or tr.Name or ""
            local low = nm:lower()
            if low:find("block", 1, true) or low:find("guard", 1, true) then e.blocking = true end
            if st.init and not st.prev[tr] then
                local p = tr.Priority
                local isAction = p == Enum.AnimationPriority.Action or p == Enum.AnimationPriority.Action2
                    or p == Enum.AnimationPriority.Action3 or p == Enum.AnimationPriority.Action4
                if isAction and not tr.Looped and tr.Length > 0.15 and tr.Length < 5 and not Ignored(nm) then
                    fired = true
                    local id = (tr.Animation and tr.Animation.AnimationId) or nm
                    OnEnemyAttack({
                        char = ch, root = r, id = id, name = nm, len = tr.Length,
                        dist = dist, facing = facing, t = now,
                    })
                end
            end
        end
    end
    st.prev, st.init = cur, true

    -- plan B: embestida detectada por velocidad
    if not fired and facing and dist < 10 and now - st.lastVel > 0.9 then
        if r.AssemblyLinearVelocity:Dot(off.Unit) > 18 then
            st.lastVel = now
            OnEnemyAttack({
                char = ch, root = r, id = "vel", name = "Embestida", len = 0.5,
                dist = dist, facing = true, t = now,
            })
        end
    end
    return e
end

local function OnDamage(frac, now)
    local H = S.Hits
    H[#H + 1] = {t = now, f = frac}
    while H[1] and now - H[1].t > 5 do table.remove(H, 1) end
    local best
    for i = #S.Recent, 1, -1 do
        local ev = S.Recent[i]
        if now - ev.t <= 0.9 then
            best = ev
            break
        end
    end
    if best then
        local rec = AnimDB[best.id]
        if rec then
            rec.hits += 1
            rec.dmg += frac
            dirty = true
        end
        S.LastAttacker, S.LastAttackerT = best.char, now
        Log(("💥 -%.0f%% por %s"):format(frac * 100, best.name))
    else
        Log(("💥 -%.0f%% (origen ?)"):format(frac * 100))
    end
end

local function Burst(window)
    local now, sum = tick(), 0
    for i = #S.Hits, 1, -1 do
        local h = S.Hits[i]
        if now - h.t > window then break end
        sum += h.f
    end
    return sum
end

local function HitCount(window)
    local now, n = tick(), 0
    for i = #S.Hits, 1, -1 do
        if now - S.Hits[i].t > window then break end
        n += 1
    end
    return n
end

local function Sense()
    local _, hum, root = GetChar()
    if not root then
        lastHP = nil
        Enemies = {}
        return
    end
    local now = tick()
    local hp = hum.Health
    if lastHP and hp < lastHP - 0.5 then
        OnDamage((lastHP - hp) / math.max(hum.MaxHealth, 1), now)
    end
    lastHP = hp
    local list = {}
    for _, pl in ipairs(Players:GetPlayers()) do
        if pl ~= player then
            local e = SenseEnemy(pl, root, now)
            if e then list[#list + 1] = e end
        end
    end
    Enemies = list
end

-- ═════════ OBJETIVOS ═════════
local function EntryOf(ch)
    for _, e in ipairs(Enemies) do
        if e.char == ch then return e end
    end
end

local function CountEnemies(radius)
    local n = 0
    for _, e in ipairs(Enemies) do
        if e.dist <= radius and not e.ff and not (CFG.SkipTeammates and e.friend) then n += 1 end
    end
    return n
end

local function NearestDist()
    local m = math.huge
    for _, e in ipairs(Enemies) do
        if e.dist < m then m = e.dist end
    end
    return m
end    
-- ═════════ DUMP (reporte de datos) ═════════
local function BuildDump()
    local L = {}
    local function add(s) L[#L + 1] = s end

    add("=== DUMP LGBG BOT v6 ===")
    add("Modo entrada: " .. tostring(Input.Mode))
    add("OffsetY: " .. tostring(Input.OffY + CFG.OffsetY))
    add("Botones calibrados: " .. tostring(calibrated))
    add("Animaciones aprendidas: " .. tostring(animCount))

    if S.Target and S.Target.Parent then
        add("-- TARGET: " .. S.Target.Name)
        local attrs = {}
        for k2, v in pairs(S.Target:GetAttributes()) do
            attrs[#attrs + 1] = k2 .. "=" .. tostring(v)
        end
        add("attrs: " .. table.concat(attrs, ", "))
    end

    add("-- ANIMACIONES ENEMIGAS APRENDIDAS (nombre|id|largo|vistas|golpes|dano%)")
    local arr = {}
    for id, r in pairs(AnimDB) do
        arr[#arr + 1] = {id = id, r = r}
    end
    table.sort(arr, function(a, b) return a.r.dmg > b.r.dmg end)
    for i = 1, math.min(#arr, 12) do
        local r = arr[i].r
        add(("%s|%s|%.2f|%d|%d|%.0f"):format(
            tostring(r.n), tostring(arr[i].id):sub(-14), r.len or 0, r.seen, r.hits, r.dmg * 100))
    end

    local text = table.concat(L, "\n")
    if #text > 6000 then text = text:sub(1, 6000) end
    return text
end

local function ShowText(title, text)
    local w = Instance.new("Frame")
    w.Size = UDim2.fromOffset(380, 230)
    w.AnchorPoint = Vector2.new(0.5, 0.5)
    w.Position = UDim2.fromScale(0.5, 0.5)
    w.BackgroundColor3 = Color3.fromRGB(18, 18, 28)
    w.BorderSizePixel = 0
    w.ZIndex = 90
    w.Parent = gui
    Corner(w, 10)
    local sc = Instance.new("UIScale", w)
    sc.Scale = math.clamp(cam().ViewportSize.Y * 0.8 / 230, 0.5, 2.5)

    local tl = mkLabel(w, title, 10, 4, 250, 20, 13, Color3.fromRGB(255, 200, 0))
    tl.ZIndex = 91
    local copy = mkBtn(w, "Copiar", 262, 4, 56, 20, Color3.fromRGB(0, 120, 90), 11)
    local close = mkBtn(w, "X", 322, 4, 50, 20, Color3.fromRGB(150, 40, 40), 11)
    copy.ZIndex, close.ZIndex = 92, 92

    local sf = Instance.new("ScrollingFrame")
    sf.Position = UDim2.fromOffset(8, 30)
    sf.Size = UDim2.fromOffset(364, 192)
    sf.BackgroundColor3 = Color3.fromRGB(8, 8, 14)
    sf.BorderSizePixel = 0
    sf.ScrollBarThickness = 6
    sf.CanvasSize = UDim2.new()
    sf.AutomaticCanvasSize = Enum.AutomaticSize.Y
    sf.ZIndex = 91
    sf.Parent = w
    local tb = Instance.new("TextBox")
    tb.Size = UDim2.new(1, -8, 0, 0)
    tb.AutomaticSize = Enum.AutomaticSize.Y
    tb.BackgroundTransparency = 1
    tb.TextColor3 = Color3.fromRGB(220, 220, 220)
    tb.Font = Enum.Font.Code
    tb.TextSize = 11
    tb.TextXAlignment = Enum.TextXAlignment.Left
    tb.TextYAlignment = Enum.TextYAlignment.Top
    tb.TextWrapped = true
    tb.MultiLine = true
    tb.ClearTextOnFocus = false
    tb.TextEditable = true
    tb.Text = text
    tb.ZIndex = 92
    tb.Parent = sf

    copy.Activated:Connect(function()
        pcall(function() setclipboard(text) end)
    end)
    close.Activated:Connect(function() w:Destroy() end)
end

local function DoDump()
    local text = BuildDump()
    pcall(function() setclipboard(text) end)
    ShowText("Dump (ya copiado si tu executor puede)", text)
end

-- ═════════ EVENTOS ═════════
local minimized = false
minBtn.Activated:Connect(function()
    minimized = not minimized
    body.Visible = not minimized
    frame.Size = UDim2.fromOffset(180, minimized and MIN_H or FULL_H)
    minBtn.Text = minimized and "+" or "—"
end)

runBtn.Activated:Connect(function()
    if S.Enabled then StopBot() else StartBot() end
end)
calBtn.Activated:Connect(function() task.spawn(Calibrate) end)
scanBtn.Activated:Connect(function() task.spawn(DoScan, false) end)
dumpBtn.Activated:Connect(function() task.spawn(DoDump) end)
testBtn.Activated:Connect(function() task.spawn(DetectInput) end)
cntBtn.Activated:Connect(function()
    task.spawn(function()
        Lock()
        Act("Contador manual", "def")
        Skill(4, true)
        Unlock()
    end)
end)

closeBtn.Activated:Connect(function()
    S.Enabled = false
    S.Alive = false
    calibrating = false
    pcall(function() RunService:UnbindFromRenderStep("LGBG_Move") end)
    pcall(function() RunService:UnbindFromRenderStep("LGBG_Cam") end)
    local c = cam()
    if camLocked and c then c.CameraType = prevCamType or Enum.CameraType.Custom end
    SetControls(true)
    if hb then hb:Disconnect() end
    local _, hum = GetChar()
    if hum then pcall(function() hum:Move(Vector3.zero, false) end) end
    Save()
    hud:Destroy()
    gui:Destroy()
end)

local acc = 0
hb = RunService.Heartbeat:Connect(function(dt)
    if not S.Alive then return end
    local ok = pcall(Sense)
    if not ok then Enemies = {} end
    acc += dt
    if acc >= 0.1 then
        acc = 0
        pcall(RefreshHUD)
    end
end)

-- ═════════ ARRANQUE ═════════
task.spawn(function()
    DetectInput()
    if not calibrated and Input.Mode then
        task.wait(0.5)
        DoScan(true)
    end
end)
