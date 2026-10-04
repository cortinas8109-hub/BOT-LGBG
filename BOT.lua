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

local function PickTarget(current)
    local best, bestScore = nil, math.huge
    local now = tick()
    for _, e in ipairs(Enemies) do
        if e.dist <= CFG.ChaseRange and not e.ff and not (CFG.SkipTeammates and e.friend) then
            local score = e.dist + e.hpPct * 0.15
            if e.char == S.LastAttacker and now - S.LastAttackerT < 5 and e.dist < 25 then score -= 12 end
            if e.char == current then score -= 8 end
            if score < bestScore then
                bestScore, best = score, e.char
            end
        end
    end
    return best
end

local function DistToTarget()
    local _, _, root = GetChar()
    local tr = S.Target and S.Target:FindFirstChild
S.Target = nil
        S.State = "MUERTO"
        Act("Esperando respawn...", "idle", true)
        task.wait(0.5)
        return
    end
    local now = tick()
    S.MyHP = hum.Health / math.max(hum.MaxHealth, 1) * 100

    -- 1) objetivo valido
    local t = S.Target
    local th = t and t:FindFirstChildOfClass("Humanoid")
    local tr = t and t:FindFirstChild("HumanoidRootPart")
    if not (t and t.Parent and th and tr) or th.Health <= 0 then
        if th and th.Health <= 0 then
            S.Kills += 1
            Act("¡Eliminado! (" .. S.Kills .. ")", "ok")
            task.wait(0.8)
        end
        S.Target = PickTarget(nil)
        S.ComboN = 0
        S.ComboToken += 1
        if not S.Target then
            S.State = "BUSCANDO"
            Act("Buscando enemigo...", "idle", true)
            task.wait(0.4)
        end
        return
    end
    if now - S.LastPick > 1 then
        S.LastPick = now
        local nt = PickTarget(t)
        if nt and nt ~= t then
            S.Target = nt
            S.ComboToken += 1
            return
        end
    end

    local dist = (tr.Position - root.Position).Magnitude
    S.Dist = dist
    S.THP = th.Health / math.max(th.MaxHealth, 1) * 100
    local entry = EntryOf(t)
    S.TargetBlocking = entry and entry.blocking or false
    if dist > CFG.ChaseRange then
        S.Target = nil
        return
    end

    -- 2) peligro: retirada
    if Burst(2.0) >= CFG.BurstPct / 100 then S.Panic = now + 4 end
    local panic = now < S.Panic
    local crowd = CountEnemies(25)
    local finishable = S.THP < 22 and S.MyHP > 20
    local wantRetreat = (S.MyHP < CFG.RetreatHP or panic or crowd >= CFG.CrowdLimit) and not finishable
    if S.Retreating then
        if finishable or now - S.RetreatStart > 15
            or (S.MyHP >= CFG.RecoverHP and not panic and crowd < CFG.CrowdLimit) then
            S.Retreating = false
        end
    elseif wantRetreat then
        S.Retreating = true
        S.RetreatStart = now
        S.ComboToken += 1
        Act("¡Retirada tactica!", "warn")
    end

    if S.Retreating then
        S.State = "HUYENDO"
        SetMove(AwayVector(root), 0.25)
        Act(("Huyendo (%d cerca)"):format(crowd), "warn", true)
        if NearestDist() < 12 and now - S.LastDash > CFG.DodgeCooldown + 0.3 then
            S.LastDash = now
            Tap("DASH", 0.06)
        end
        task.wait(0.1)
        return
    end

    -- 3) acercarse
    if dist > CFG.AttackRange then
        S.State = "ACERCANDOSE"
        local dir = (tr.Position - root.Position) * Vector3.new(1, 0, 1)
        dir = dir.Magnitude > 0.1 and dir.Unit or root.CFrame.LookVector
        SetMove(dir, 0.2)
        Act("Acercandose", "move", true)
        if dist > 16 and DashReady() and now - S.LastAttackerT > 1.5 then
            Dash("Dash hacia enemigo")
        end
        if now < S.PunishUntil and dist < 14 and Ready(1) then Skill(1) end
        if now - S.StuckT > 1.5 then
            if (root.Position - S.StuckPos).Magnitude < 1.5 then
                Act("Atascado: salto", "warn")
                hum.Jump = true
            end
            S.StuckT, S.StuckPos = now, root.Position
        end
        task.wait(0.08)
        return
    end

    -- 4) pelear
    S.State = "COMBATE"
    S.StuckT, S.StuckPos = now, root.Position
    FaceTarget()
    RunCombo()
    Pause(0.2)
end

local function MainLoop(run)
    while S.Enabled and S.Alive and S.Run == run do
        local ok, err = pcall(Step)
        if not ok then
            Act("Error: " .. tostring(err):sub(1, 50), "warn")
            task.wait(0.5)
        end
        task.wait(0.03)
    end
end

local runBtn -- boton iniciar (se crea en el panel)
local function SetRunUI()
    if not runBtn then return end
    runBtn.Text = S.Enabled and "⏹ DETENER" or "▶ INICIAR"
    runBtn.BackgroundColor3 = S.Enabled and Color3.fromRGB(200, 50, 50) or Color3.fromRGB(0, 170, 90)
end

local function StartBot()
    if S.Enabled then return end
    if not Input.Mode then
        Act("Sin toques: pulsa PROBAR", "warn")
        return
    end
    S.Enabled = true
    S.Run += 1
    S.Target, S.Retreating, S.Lock = nil, false, 0
    reacting = false
    SetControls(false)
    SetRunUI()
    Act("Bot iniciado", "ok")
    task.spawn(MainLoop, S.Run)
end

local function StopBot()
    S.Enabled = false
    S.MoveVec = nil
    local _, hum = GetChar()
    if hum then pcall(function() hum:Move(Vector3.zero, false) end) end
    SetControls(true)
    SetRunUI()
    Act("Detenido", "idle")
end

-- ═════════ PANEL COMPACTO ═════════
local function Corner(o, r)
    Instance.new("UICorner", o).CornerRadius = UDim.new(0, r or 7)
end

local function mkBtn(parent, text, x, y, w, h, color, size)
    local b = Instance.new("TextButton")
    b.Position = UDim2.fromOffset(x, y)
    b.Size = UDim2.fromOffset(w, h)
    b.BackgroundColor3 = color
    b.Text = text
    b.TextColor3 = Color3.new(1, 1, 1)
    b.Font = Enum.Font.GothamBold
    b.TextSize = size or 12
    b.BorderSizePixel = 0
    b.Parent = parent
    Corner(b, 7)
    return b
end

local function mkLabel(parent, text, x, y, w, h, size, color)
    local l = Instance.new("TextLabel")
    l.Position = UDim2.fromOffset(x, y)
    l.Size = UDim2.fromOffset(w, h)
    l.BackgroundTransparency = 1
    l.Text = text
    l.TextColor3 = color or Color3.new(1, 1, 1)
    l.Font = Enum.Font.GothamBold
    l.TextSize = size or 11
    l.TextXAlignment = Enum.TextXAlignment.Left
    l.Parent = parent
    return l
end

local FULL_H, MIN_H = 204, 24
local frame = Instance.new("Frame")
frame.Size = UDim2.fromOffset(180, FULL_H)
frame.Position = UDim2.fromOffset(8, 8)
frame.BackgroundColor3 = Color3.fromRGB(18, 18, 28)
frame.BackgroundTransparency = 0.1
frame.BorderSizePixel = 0
frame.Active = true
frame.Draggable = true
frame.ClipsDescendants = true
frame.Parent = gui
Corner(frame, 10)

local pscale = Instance.new("UIScale", frame)
pscale.Scale = math.clamp(cam().ViewportSize.Y * 0.42 / FULL_H, 0.5, 2.2)

mkLabel(frame, "🥋 BOT v6", 8, 3, 120, 18, 12, Color3.fromRGB(255, 200, 0))
local minBtn = mkBtn(frame, "—", 148, 2, 28, 20, Color3.fromRGB(60, 60, 80), 12)

local body = Instance.new("Frame")
body.Position = UDim2.fromOffset(0, 24)
body.Size = UDim2.fromOffset(180, FULL_H - 24)
body.BackgroundTransparency = 1
body.Parent = frame

runBtn = mkBtn(body, "▶ INICIAR", 6, 2, 168, 30, Color3.fromRGB(0, 170, 90), 14)
local infoA = mkLabel(body, "🎮 probando...", 6, 35, 168, 14, 11, Color3.fromRGB(190, 190, 190))
local infoB = mkLabel(body, "📍 default · K:0", 6, 49, 168, 14, 11, Color3.fromRGB(190, 190, 190))

local function mkSwitch(text, key, x)
    local b = mkBtn(body, "", x, 66, 39, 22, Color3.fromRGB(0, 130, 85), 10)
    local function refresh()
        b.Text = text .. (CFG[key] and " ✔" or " ✘")
        b.BackgroundColor3 = CFG[key] and Color3.fromRGB(0, 130, 85) or Color3.fromRGB(90, 90, 90)
    end
    b.Activated:Connect(function()
        CFG[key] = not CFG[key]
        refresh()
    end)
    refresh()
end
mkSwitch("ESQ", "AutoDodge", 6)
mkSwitch("BLQ", "AutoBlock", 49)
mkSwitch("CNT", "AutoCounter", 92)
mkSwitch("CAM", "LockCam", 135)

local calBtn = mkBtn(body, "📍 Calibrar", 6, 92, 82, 24, Color3.fromRGB(150, 100, 0), 11)
local scanBtn = mkBtn(body, "🔎 Escanear", 92, 92, 82, 24, Color3.fromRGB(0, 110, 150), 11)
local dumpBtn = mkBtn(body, "📋 Dump", 6, 120, 82, 24, Color3.fromRGB(90, 70, 140), 11)
local testBtn = mkBtn(body, "🎮 Probar", 92, 120, 82, 24, Color3.fromRGB(70, 70, 120), 11)
local cntBtn = mkBtn(body, "🛡 Contador", 6, 148, 82, 24, Color3.fromRGB(180, 50, 50), 11)
local closeBtn = mkBtn(body, "✖ Cerrar", 92, 148, 82, 24, Color3.fromRGB(80, 80, 80), 11)

-- ═════════ HUD: cartel de acciones arriba al centro ═════════
local banner = Instance.new("Frame")
banner.AnchorPoint = Vector2.new(0.5, 0)
banner.Position = UDim2.new(0.5, 0, 0, 4)
banner.Size = UDim2.fromOffset(360, 58)
banner.BackgroundColor3 = Color3.fromRGB(10, 10, 16)
banner.BackgroundTransparency = 0.4
banner.BorderSizePixel = 0
banner.Parent = hud
Corner(banner, 10)
local bscale = Instance.new("UIScale", banner)
bscale.Scale = math.clamp(cam().ViewportSize.Y / 420, 0.55, 2.4)

local function bLabel(y, h, size)
    local l = Instance.new("TextLabel")
    l.Position = UDim2.fromOffset(0, y)
    l.Size = UDim2.fromOffset(360, h)
    l.BackgroundTransparency = 1
    l.TextColor3 = Color3.new(1, 1, 1)
    l.Font = Enum.Font.GothamBold
    l.TextSize = size
    l.Parent = banner
    return l
end
local bl1 = bLabel(2, 24, 17)
local bl2 = bLabel(26, 16, 12)
local bl3 = bLabel(42, 14, 11)
local logLbl = Instance.new("TextLabel")
logLbl.Position = UDim2.fromOffset(0, 60)
logLbl.Size = UDim2.fromOffset(360, 56)
logLbl.BackgroundTransparency = 1
logLbl.TextColor3 = Color3.fromRGB(235, 235, 235)
logLbl.TextStrokeTransparency = 0.5
logLbl.Font = Enum.Font.Gotham
logLbl.TextSize = 11
logLbl.TextYAlignment = Enum.TextYAlignment.Top
logLbl.TextWrapped = true
logLbl.Parent = banner

local hb
local lastSave = tick()
local function RefreshHUD()
    local _, _, root = GetChar()
    local now = tick()
    local t = S.Target

    bl1.Text = (KIND_ICON[S.Kind] or "•") .. " " .. S.Action
    bl1.TextColor3 = KIND_COLOR[S.Kind] or Color3.new(1, 1, 1)
    bl2.Text = "Siguiente: " .. S.Next
    if t and t.Parent then
        bl3.Text = ("🎯 %s  ❤%.0f%%  📏%.0f   |   yo ❤%.0f%%   %s"):format(t.Name, S.THP, S.Dist, S.MyHP, S.State)
    else
        bl3.Text = ("sin objetivo   |   yo ❤%.0f%%   %s"):format(S.MyHP, S.State)
    end
    logLbl.Text = table.concat(S.Log, "\n")

    -- highlight y cartel del objetivo
    if t and t.Parent and S.Enabled then
        thl.Adornee = t
        thl.Enabled = true
        local c
        if now < S.TargetFlash then
            c = Color3.fromRGB(255, 40, 40)
        elseif S.THP > 50 then
            c = Color3.fromRGB(255, 235, 60)
        elseif S.THP > 25 then
            c = Color3.fromRGB(255, 150, 0)
        else
            c = Color3.fromRGB(255, 60, 60)
        end
        thl.FillColor, thl.OutlineColor = c, c
        local r = t:FindFirstChild("HumanoidRootPart")
        if r then
            tbb.Adornee = r
            tbb.Enabled = true
            tbl.Text = ("🎯 %s\n❤ %.0f%% · %.0f"):format(t.Name, S.THP, S.Dist)
        end
    else
        thl.Enabled = false
        tbb.Enabled = false
    end

    -- cartel sobre mi personaje: lo que esta haciendo el bot
    if root and S.Enabled then
        mbb.Adornee = root
        mbb.Enabled = true
        mbl.Text = S.Action
        mbl.TextColor3 = KIND_COLOR[S.Kind] or Color3.new(1, 1, 1)
    else
        mbb.Enabled = false
    end

    -- enemigos que estan atacando
    for ch, h in pairs(thrHL) do
        if not ch.Parent then
            h:Destroy()
            thrHL[ch] = nil
        elseif now > (thrExp[ch] or 0) then
            h.Enabled = false
        end
    end

    -- panel
    local m
    if S.Probing then
        m = "probando toques..."
    elseif Input.Mode then
        m = ("modo %s ✔ Y%+.0f"):format(Input.Mode, Input.OffY)
    else
        m = "SIN TOQUES ✘"
    end
    infoA.Text = "🎮 " .. m
    infoB.Text = ("📍 %s · K:%d"):format(calibrated and "calibrado" or "default", S.Kills)

    if dirty and now - lastSave > 20 then
        lastSave = now
        Save()
    end
end

-- ═════════ DETECTAR MODO DE TOQUES ═════════
local detecting = false
local function DetectInput()
    if detecting then return end
    detecting = true
    S.Probing = true
    Input.Mode, Input.OffY, Input.InDelta = nil, 0, Vector2.zero

    local hit, hitPos = false, nil
    local function mk(w, h, text)
        local b = Instance.new("TextButton")
        b.Size = UDim2.fromOffset(w, h)
        b.AnchorPoint = Vector2.new(0.5, 0.5)
        b.Position = UDim2.fromScale(0.5, 0.5)
        b.ZIndex = 80
        b.Text = text
        b.TextSize = 14
        b.Parent = gui
        b.InputBegan:Connect(function(i)
            if i.UserInputType == Enum.UserInputType.Touch or i.UserInputType == Enum.UserInputType.MouseButton1 then
                hit = true
                hitPos = Vector2.new(i.Position.X, i.Position.Y)
            end
        end)
        return b
    end
    local function probe(mode, x, y)
        hit, hitPos = false, nil
        local id = nextId()
        pcall(raw, mode, id, x, y, 0)
        task.wait(0.1)
        pcall(raw, mode, id, x, y, 2)
        task.wait(0.25)
        return hit
    end

    local k = math.clamp(cam().ViewportSize.Y / 360, 0.8, 3)
    local big = mk(220 * k, 120 * k, "probando toques...")
    task.wait(0.3)
    local c = big.AbsolutePosition + big.AbsoluteSize / 2
    for _, m in ipairs({"A", "B", "M"}) do
        if probe(m, c.X, c.Y) then
            Input.Mode = m
            break
        end
    end
    big:Destroy()

    -- ajuste vertical (barra superior) con una tira delgada
    if Input.Mode then
        local strip = mk(260 * k, 12 * k, "")
        task.wait(0.3)
        local sc = strip.AbsolutePosition + strip.AbsoluteSize / 2
        local ins = GuiService:GetGuiInset()
        local tried = {}
        for _, off in ipairs({0, ins.Y, -ins.Y, 36, -36, 58, -58, 24, -24}) do
            if not tried[off] then
                tried[off] = true
                if probe(Input.Mode, sc.X, sc.Y + off) then
                    Input.OffY = off
                    Input.InDelta = hitPos - sc
                    break
                end
            end
        end
        strip:Destroy()
    end

    if Input.Mode then
        Log("🎮 Toques OK (modo " .. Input.Mode .. ")")
    else
        Log("🎮 Los toques NO funcionan")
    end
    S.Probing = false
    detecting = false
end

-- ═════════ CALIBRAR BOTONES (tocas cada boton del juego) ═════════
local calibrating = false
local function Calibrate()
    if calibrating then return end
    calibrating = true
    frame.Visible = false
    local vs0 = cam().ViewportSize
    local k = math.clamp(vs0.Y / 360, 0.8, 3)

    local cap = Instance.new("TextButton")
    cap.Size = UDim2.fromScale(1, 1)
    cap.BackgroundColor3 = Color3.new(0, 0, 0)
    cap.BackgroundTransparency = 0.78
    cap.Text = ""
    cap.AutoButtonColor = false
    cap.ZIndex = 60
    cap.Parent = gui

    local got
    cap.InputBegan:Connect(function(inp)
        if inp.UserInputType == Enum.UserInputType.Touch or inp.UserInputType == Enum.UserInputType.MouseButton1 then
            got = Vector2.new(inp.Position.X, inp.Position.Y)
        end
    end)

    local ban = Instance.new("Frame")
    ban.AnchorPoint = Vector2.new(0.5, 0)
    ban.Position = UDim2.new(0.5, 0, 0, 8)
    ban.Size = UDim2.fromOffset(330 * k, 52 * k)
    ban.BackgroundColor3 = Color3.fromRGB(18, 18, 28)
    ban.BorderSizePixel = 0
    ban.ZIndex = 70
    ban.Parent = gui
    Corner(ban, 10)
    local msg = Instance.new("TextLabel")
    msg.Position = UDim2.fromOffset(8 * k, 0)
    msg.Size = UDim2.fromOffset(240 * k, 52 * k)
    msg.BackgroundTransparency = 1
    msg.TextColor3 = Color3.fromRGB(255, 200, 0)
    msg.Font = Enum.Font.GothamBold
    msg.TextSize = 13 * k
    msg.TextWrapped = true
    msg.ZIndex = 71
    msg.Parent = ban
    local cancel = Instance.new("TextButton")
    cancel.Position = UDim2.fromOffset(250 * k, 8 * k)
    cancel.Size = UDim2.fromOffset(72 * k, 36 * k)
    cancel.BackgroundColor3 = Color3.fromRGB(150, 40, 40)
    cancel.Text = "Cancelar"
    cancel.TextColor3 = Color3.new(1, 1, 1)
    cancel.Font = Enum.Font.GothamBold
    cancel.TextSize = 12 * k
    cancel.ZIndex = 72
    cancel.Parent = ban
    Corner(cancel, 8)
    cancel.Activated:Connect(function() calibrating = false end)

    for i, name in ipairs(BTN_ORDER) do
        if not calibrating then break end
        msg.Text = ("Toca el boton del juego:\n%s  (%d/%d)"):format(BTN_NAMES[name], i, #BTN_ORDER)
        got = nil
        repeat task.wait() until got or not calibrating
        if got and calibrating then
            local vs = cam().ViewportSize
            local s = got - Input.InDelta
            Pos[name] = Vector2.new(s.X / vs.X, s.Y / vs.Y)
            Marker(s.X, s.Y, SHORT[name], Color3.fromRGB(100, 255, 140), 1.2, 30, false)
            task.wait(0.4)
        end
    end

    if calibrating then
        calibrated = true
        Save()
        Log("📍 Botones calibrados")
    end
    cap:Destroy()
    ban:Destroy()
    frame.Visible = true
    calibrating = false
end

-- ═════════ ESCANEAR LOS BOTONES REALES DEL JUEGO ═════════
local function VisibleChain(o)
    while o and o ~= game do
        if o:IsA("GuiObject") and not o.Visible then return false end
        if o:IsA("ScreenGui") and not o.Enabled then return false end
        o = o.Parent
    end
    return true
end

local function CenterOf(b)
    local sg = b:FindFirstAncestorOfClass("ScreenGui")
    local ins = (sg and sg.IgnoreGuiInset) and Vector2.zero or GuiService:GetGuiInset()
    return b.AbsolutePosition + b.AbsoluteSize / 2 + ins
end

local function CollectButtons()
    local out, vs = {}, cam().ViewportSize
    local roots = {}
    local pg = player:FindFirstChildOfClass("PlayerGui")
    if pg then roots[#roots + 1] = pg end
    pcall(function() roots[#roots + 1] = game:GetService("CoreGui") end)
    for _, root in ipairs(roots) do
        local okD, desc = pcall(function() return root:GetDescendants() end)
        if okD then
            for _, d in ipairs(desc) do
                if d:IsA("GuiButton") and not d:IsDescendantOf(gui) and not d:IsDescendantOf(hud) and VisibleChain(d) then
                    local sz = d.AbsoluteSize
                    if sz.X >= 16 and sz.Y >= 16 and sz.X <= 420 and sz.Y <= 420 then
                        local c = CenterOf(d)
                        if c.X > 0 and c.Y > 0 and c.X < vs.X and c.Y < vs.Y then
                            local txt = d:IsA("TextButton") and d.Text or ""
                            if txt == "" then
                                local tl = d:FindFirstChildWhichIsA("TextLabel", true)
                                if tl then txt = tl.Text end
                            end
                            out[#out + 1] = {inst = d, c = c, sz = sz, text = txt, name = d.Name}
                        end
                    end
                end
            end
        end
    end
    return out
end

local PATTERNS = {
    ATTACK = {"m1", "attack", "punch", "atk", "melee", "basic"},
    DASH = {"dash", "dodge", "evade", "roll"},
    BLOCK = {"block", "guard", "parry", "defend"},
    JUMP = {"jump"},
}
local function hasAny(s, words)
    for _, w in ipairs(words) do
        if s:find(w, 1, true) then return true end
    end
    return false
end

local function AutoMap(list)
    local vs = cam().ViewportSize
    local found = {}
    local function consider(act, b)
        local f = DEFAULTFRAC[act]
        local dflt = Vector2.new(f.X * vs.X, f.Y * vs.Y)
        local dist = (b.c - dflt).Magnitude
        if not found[act] or dist < found[act].dist then found[act] = {btn = b, dist = dist} end
    end
    for _, b in ipairs(list) do
        local lower = (b.name .. " " .. b.text):lower()
        for act, words in pairs(PATTERNS) do
            if hasAny(lower, words) then consider(act, b) end
        end
        local n = lower:match("skill[%s_%-]*(%d)") or lower:match("move[%s_%-]*(%d)")
            or lower:match("ability[%s_%-]*(%d)") or lower:match("slot[%s_%-]*(%d)")
            or lower:match("hotbar[%s_%-]*(%d)")
        if not n then
            n = b.name:match("^(%d)$") or b.text:match("^%s*(%d)%s*$")
        end
        n = tonumber(n)
        if n and n >= 1 and n <= 4 then consider("SKILL_" .. n, b) end
    end
    return found
end

local function DoScan(auto)
    local list = CollectButtons()
    local found = AutoMap(list)
    local vs = cam().ViewportSize
    local count = 0
    for _, name in ipairs(BTN_ORDER) do
        local f = found[name]
        if f then
            count += 1
            Pos[name] = Vector2.new(f.btn.c.X / vs.X, f.btn.c.Y / vs.Y)
            Marker(f.btn.c.X, f.btn.c.Y, SHORT[name] .. " ✔", Color3.fromRGB(100, 255, 140), 6, 28, true)
        else
            local p = Pos[name]
            Marker(p.X * vs.X, p.Y * vs.Y, SHORT[name] .. " ?", Color3.fromRGB(255, 80, 80), 6, 24, true)
        end
    end
    if count > 0 then
        calibrated = true
        Save()
    end
    Log(("🔎 %d/8 botones detectados (%d vistos)"):format(count, #list))
    if not auto and count < 8 then
        Log("Los rojos (?) usan posicion por defecto: usa Calibrar")
    end
end

-- ═════════ DUMP (para que me mandes los datos reales del juego) ═════════
local function BuildDump()
    local vs = cam().ViewportSize
    local ins = GuiService:GetGuiInset()
    local L = {}
    local function add(s) L[#L + 1] = s end
    add(("LGBG DUMP v6 | viewport %.0fx%.0f | inset %.0f,%.0f | modo %s | offY %.0f"):format(
        vs.X, vs.Y, ins.X, ins.Y, tostring(Input.Mode), Input.OffY))

    add("-- BOTONES VISIBLES (nombre|clase|texto|fx,fy|tamano)")
    local list = CollectButtons()
    table.sort(list, function(a, b) return a.c.X < b.c.X end)
    for i = 1, math.min(#list, 45) do
        local b = list[i]
        add(("%s|%s|'%s'|%.3f,%.3f|%.0fx%.0f"):format(
            b.name, b.inst.ClassName, b.text:sub(1, 12), b.c.X / vs.X, b.c.Y / vs.Y, b.sz.X, b.sz.Y))
    end

    local ch, hum = GetChar()
    if ch then
        add("-- MI PERSONAJE")
        local attrs = {}
        for k2, v in pairs(ch:GetAttributes()) do attrs[#attrs + 1] = k2 .. "=" .. tostring(v) end
        add("attrs: " .. table.concat(attrs, ", "))
        add("estado: " .. tostring(hum:GetState()) .. " | ws " .. tostring(hum.WalkSpeed))
        local tools = {}
        local bp = player:FindFirstChildOfClass("Backpack")
        if bp then for _, tl in ipairs(bp:GetChildren()) do tools[#tools + 1] = tl.Name end end
        for _, tl in ipairs(ch:GetChildren()) do
            if tl:IsA("Tool") then tools[#tools + 1] = "[eq]" .. tl.Name end
        end
        add("tools: " .. table.concat(tools, ", "))
    end

    if S.Target and S.Target.Parent then
        add("-- TARGET: " .. S.Target.Name)
        local attrs = {}
        for k2, v in pairs(S.Target:GetAttributes()) do attrs[#attrs + 1] = k2 .. "=" .. tostring(v) end
        add("attrs: " .. table.concat(attrs, ", "))
    end

    add("-- ANIMACIONES ENEMIGAS APRENDIDAS (nombre|id|largo|vistas|golpes|dano%)")
    local arr = {}
    for id, r in pairs(AnimDB) do arr[#arr + 1] = {id = id, r = r} end
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