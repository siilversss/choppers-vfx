--[[
	VFXKit: hand-tuned element effect kits for every weapon.

	K.make(theme, variant, c1, c2, power) -> element { trail, step(S, x), impact(x) }
	  theme   : steel, fire, dragon, ice, lightning, nature, petal, arcane, void, holy, blood,
	            toxic, crystal, cosmic, eclipse, prismatic, solar, tide
	  variant : 1..4, picks one of the theme's hand-built impacts (so weapons of one element differ)
	  power   : 0 Base .. 1 Common .. 2 Uncommon .. 3 Rare (steel only) | 1 Epic, 2 Legendary, 3 Mythic, 4 Godly

	Principles: an impact frame (flash + light + camera kick), then layered textured follow-through;
	ground marks that linger and fade slowly; physical debris tinted by the ground it came from;
	jittered sizes, angles and timings so no two hits look stamped out.
]]
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local VT = require(script.Parent:WaitForChild("VFXTextures"))

local V, C = Vector3.new, Color3.fromRGB
local NS, NR = NumberSequence.new, NumberRange.new
local WHITE, BLACK = Color3.new(1, 1, 1), Color3.new(0, 0, 0)
local TAU = math.pi * 2
local K = {}

---------------------------------------------------------------- small helpers
local function rnd(a, b) return a + math.random() * (b - a) end
local function jitter(cf, xz, rotY) return cf * CFrame.new(rnd(-xz, xz), 0, rnd(-xz, xz)) * CFrame.Angles(0, rnd(-rotY, rotY), 0) end
local function seq(...)
	local k, args = {}, { ... }
	for i = 1, #args, 2 do table.insert(k, NumberSequenceKeypoint.new(args[i], args[i + 1])) end
	return NumberSequence.new(k)
end
local function cseq(...)
	local k, args = {}, { ... }
	for i = 1, #args, 2 do table.insert(k, ColorSequenceKeypoint.new(args[i], args[i + 1])) end
	return ColorSequence.new(k)
end
local function tw(o, t, goal, style, dir)
	local x = TweenService:Create(o, TweenInfo.new(t, style or Enum.EasingStyle.Quad, dir or Enum.EasingDirection.Out), goal)
	x:Play(); return x
end
local function part(o)
	local p = Instance.new(o.class or "Part")
	p.Anchored = o.anchored ~= false; p.CanCollide = false; p.CanQuery = false; p.CanTouch = false; p.CastShadow = false
	p.Material = o.mat or Enum.Material.Neon; p.Color = o.color or WHITE
	p.Size = o.size or V(0.2, 0.2, 0.2); p.CFrame = o.cf or CFrame.new(); p.Transparency = o.trans or 0
	if o.shape then p.Shape = o.shape end
	p.Parent = o.parent or workspace
	if o.life then Debris:AddItem(p, o.life) end
	return p
end
local function vivid(c)
	local h, s, v = c:ToHSV()
	if s < 0.12 then return Color3.fromHSV(h, s, math.max(v, 0.93)) end
	return Color3.fromHSV(h, math.clamp(s * 1.15 + 0.08, 0, 1), math.max(v, 0.95))
end
K.vivid = vivid

-- one-shot particle burst. o = { cf, tex, color, size, life, n, speed, spread, accel, drag, le, trans, flip, rot, z, orient, hold, emitDir }
local function burst(o)
	local a = part({ cf = o.cf, trans = 1, life = o.hold or 3 })
	local e = Instance.new("ParticleEmitter")
	e.Texture = o.tex; e.Color = o.color or ColorSequence.new(WHITE); e.Size = o.size or NS(1)
	e.Transparency = o.trans or NS(0, 1); e.Lifetime = o.life or NR(0.5, 0.8)
	e.Speed = o.speed or NR(0, 0); e.SpreadAngle = o.spread or Vector2.new(180, 180)
	e.Acceleration = o.accel or Vector3.zero; e.Drag = o.drag or 0; e.LightEmission = o.le or 1; e.LightInfluence = 0
	e.Rotation = o.rotation or NR(0, 360); e.RotSpeed = o.rot or NR(-40, 40); e.ZOffset = o.z or 0
	if o.orient then e.Orientation = o.orient end
	if o.emitDir then e.EmissionDirection = o.emitDir end
	if o.flip then e.FlipbookLayout = Enum.ParticleFlipbookLayout.Grid4x4; e.FlipbookMode = Enum.ParticleFlipbookMode.OneShot end
	e.Enabled = false; e.Parent = a
	e:Emit(o.n or 1)
	return a, e
end
-- persistent emitter on a part (presence); returned so it can be cleaned up
local function emitter(parent, props)
	local e = Instance.new("ParticleEmitter")
	e.LightInfluence = 0; e.Rotation = NR(0, 360)
	for k, v in pairs(props) do if k ~= "flip" then e[k] = v end end
	if props.flip then e.FlipbookLayout = Enum.ParticleFlipbookLayout.Grid4x4; e.FlipbookMode = Enum.ParticleFlipbookMode.OneShot end
	e.Parent = parent
	return e
end
-- glowing two-sided card in the part's XZ plane
local function card(cf, size, image, color, trans, life, bright, parent)
	local p = part({ size = V(size, 0.05, size), cf = cf, trans = 1, life = life, parent = parent })
	local imgs = {}
	for _, face in ipairs({ Enum.NormalId.Top, Enum.NormalId.Bottom }) do
		local g = Instance.new("SurfaceGui"); g.Face = face; g.LightInfluence = 0; g.Brightness = bright or 2.5
		g.SizingMode = Enum.SurfaceGuiSizingMode.FixedSize; g.CanvasSize = Vector2.new(256, 256)
		local im = Instance.new("ImageLabel"); im.BackgroundTransparency = 1; im.Size = UDim2.fromScale(1, 1)
		im.Image = image; im.ImageColor3 = color; im.ImageTransparency = trans or 0; im.Parent = g
		g.Parent = p; imgs[#imgs + 1] = im
	end
	return p, imgs
end
local function fadeImgs(imgs, t, delay)
	task.delay(delay or 0, function() for _, im in ipairs(imgs) do if im.Parent then tw(im, t, { ImageTransparency = 1 }) end end end)
end
-- a mark left on the ground: pops in slightly oversized, settles, lingers, fades slowly
local function groundMark(hit, image, color, size, hold, trans, bright)
	local cf = jitter(hit * CFrame.new(0, 0.06 + math.random() * 0.02, 0), 0.25, math.pi)
	local s0 = size * rnd(0.9, 1.1)
	local c, imgs = card(cf, s0 * 0.55, image, color, trans or 0, hold + 1.5, bright or 1.2)
	tw(c, 0.14, { Size = V(s0, 0.05, s0) }, Enum.EasingStyle.Back)
	fadeImgs(imgs, 1.2, hold)
	return c, imgs
end
local function flareStreak(pos, color, width, life)
	local a = part({ cf = CFrame.new(pos), trans = 1, life = life + 0.2 })
	local b = Instance.new("BillboardGui"); b.Size = UDim2.fromScale(width, width / 4); b.LightInfluence = 0; b.Brightness = 3; b.Parent = a
	local im = Instance.new("ImageLabel"); im.BackgroundTransparency = 1; im.Size = UDim2.fromScale(1, 1); im.Image = VT.flareStreak; im.ImageColor3 = color; im.Parent = b
	tw(im, life, { ImageTransparency = 1 }); tw(b, life, { Size = UDim2.fromScale(width * 1.7, width / 9) })
end
local function light(pos, color, range, bright, t)
	local a = part({ cf = CFrame.new(pos), trans = 1, life = t + 0.2 })
	local l = Instance.new("PointLight"); l.Color = color; l.Range = range; l.Brightness = bright; l.Shadows = false; l.Parent = a
	tw(l, t, { Brightness = 0 })
	return l
end
-- a textured beam between two points (lightning bolts, light columns)
local function beam(p0, p1, tex, color, width, life, opts)
	opts = opts or {}
	local a = part({ cf = CFrame.new(p0), trans = 1, life = life + 0.2 })
	local b = part({ cf = CFrame.new(p1), trans = 1, life = life + 0.2 })
	local a0 = Instance.new("Attachment"); a0.Parent = a
	local a1 = Instance.new("Attachment"); a1.Parent = b
	local bm = Instance.new("Beam"); bm.Attachment0 = a0; bm.Attachment1 = a1; bm.Texture = tex
	bm.TextureMode = Enum.TextureMode.Stretch; bm.TextureLength = 1; bm.TextureSpeed = opts.speed or 0
	bm.Color = ColorSequence.new(color); bm.LightEmission = 1; bm.LightInfluence = 0; bm.FaceCamera = true
	bm.Width0 = width; bm.Width1 = opts.width1 or width; bm.Segments = 1
	bm.Transparency = NS(opts.trans or 0); bm.Parent = a
	task.delay(opts.hold or 0, function()
		local t0 = os.clock()
		local c
		c = RunService.Heartbeat:Connect(function()
			local u = (os.clock() - t0) / math.max(life - (opts.hold or 0), 0.01)
			if u >= 1 or not bm.Parent then c:Disconnect(); return end
			bm.Transparency = NS((opts.trans or 0) + (1 - (opts.trans or 0)) * u)
			if opts.flicker then bm.TextureLength = rnd(0.7, 1.3) end
		end)
	end)
	return bm
end

---------------------------------------------------------------- camera kick (only for your own hits)
local shakeAmp, shakeT = 0, 0
RunService:BindToRenderStep("VFXKitShake", Enum.RenderPriority.Camera.Value + 1, function(dt)
	if shakeAmp <= 0.001 then return end
	shakeT += dt
	local cam = workspace.CurrentCamera
	if cam then
		local a = shakeAmp
		cam.CFrame = cam.CFrame * CFrame.new(math.noise(shakeT * 22, 0) * a, math.noise(0, shakeT * 22) * a, 0) * CFrame.Angles(0, 0, math.noise(shakeT * 18, 7) * a * 0.04)
	end
	shakeAmp = math.max(0, shakeAmp - dt * shakeAmp * 9 - dt * 0.05)
end)
local function kick(x, amount)
	local lp = Players.LocalPlayer
	if lp and x.char and x.char == lp.Character then shakeAmp = math.max(shakeAmp, amount) end
end

---------------------------------------------------------------- physical debris (simple client sim, ground-tinted)
local debrisList = {}
RunService.Heartbeat:Connect(function(dt)
	for i = #debrisList, 1, -1 do
		local d = debrisList[i]
		d.age += dt
		if d.age > d.life or not d.p.Parent then
			if d.p.Parent then d.p:Destroy() end
			table.remove(debrisList, i)
		else
			d.v = d.v + V(0, -70 * dt, 0)
			local pos = d.p.Position + d.v * dt
			local floor = d.gy + d.p.Size.Y * 0.5
			if pos.Y < floor then
				pos = V(pos.X, floor, pos.Z)
				d.v = V(d.v.X * 0.55, -d.v.Y * 0.32, d.v.Z * 0.55)
				d.spin = d.spin * 0.6
			end
			d.p.CFrame = CFrame.new(pos) * (d.p.CFrame - d.p.Position) * CFrame.Angles(d.spin.X * dt, d.spin.Y * dt, d.spin.Z * dt)
			if d.age > d.life - 0.35 then d.p.Transparency = math.min(1, d.p.Transparency + dt * 3) end
		end
	end
end)
local function groundInfo(hit)
	local rp = RaycastParams.new(); rp.FilterType = Enum.RaycastFilterType.Exclude
	local lp = Players.LocalPlayer
	rp.FilterDescendantsInstances = { lp and lp.Character or workspace.CurrentCamera }
	local r = workspace:Raycast(hit.Position + V(0, 2, 0), V(0, -6, 0), rp)
	if r then
		if r.Instance:IsA("Terrain") then return workspace.Terrain:GetMaterialColor(r.Material), r.Material, r.Position.Y end
		return r.Instance.Color, r.Instance.Material, r.Position.Y
	end
	return C(120, 110, 100), Enum.Material.Slate, hit.Position.Y
end
local function debris(hit, n, power, tint, mat)
	local col, gmat, gy = groundInfo(hit)
	for i = 1, n do
		local s = rnd(0.18, 0.42) * (0.8 + power * 0.15)
		local p = part({ size = V(s, s * rnd(0.6, 1), s * rnd(0.7, 1.2)), cf = hit * CFrame.new(rnd(-0.6, 0.6), 0.3, rnd(-0.6, 0.6)) * CFrame.Angles(rnd(0, 6), rnd(0, 6), rnd(0, 6)),
			color = tint or col:Lerp(BLACK, rnd(0, 0.25)), mat = mat or ((gmat == Enum.Material.Neon or gmat == Enum.Material.Glass) and Enum.Material.Slate or gmat) })
		local ang = rnd(0, TAU)
		local out = rnd(6, 13) * (0.8 + power * 0.12)
		table.insert(debrisList, { p = p, v = V(math.cos(ang) * out, rnd(13, 22) * (0.8 + power * 0.1), math.sin(ang) * out), spin = V(rnd(-9, 9), rnd(-9, 9), rnd(-9, 9)), gy = gy, age = 0, life = rnd(1.4, 2.2) })
	end
end
local function dustPuff(hit, n, size, tint)
	local col = tint or select(1, groundInfo(hit)):Lerp(WHITE, 0.35)
	for i = 1, n do
		local ang = (i / n) * TAU + rnd(-0.3, 0.3)
		local dir = V(math.cos(ang), 0, math.sin(ang))
		burst({ cf = CFrame.lookAt(hit.Position + V(0, 0.4, 0), hit.Position + V(0, 0.4, 0) + dir + V(0, 0.35, 0)), tex = VT.dust4x4, flip = true,
			color = ColorSequence.new(col, col:Lerp(BLACK, 0.2)), size = seq(0, size * 0.5, 1, size * rnd(1.2, 1.6)), trans = seq(0, 0.15, 1, 1),
			life = NR(0.55, 0.85), speed = NR(4, 8), spread = Vector2.new(12, 12), drag = 4, le = 0, n = 1, emitDir = Enum.NormalId.Front, z = -1 })
	end
end
local function sparks(cf, c1, c2, n, speed, size, life)
	burst({ cf = cf, tex = VT.sparkStreak, orient = Enum.ParticleOrientation.VelocityParallel, color = ColorSequence.new(c2, c1), size = NS(size or 0.5, 0),
		life = life or NR(0.25, 0.5), speed = NR(speed * 0.6, speed), spread = Vector2.new(80, 80), accel = V(0, -40, 0), drag = 2, n = n, le = 0.85 })
end
local function impactFrame(hit, c1, c2, size, P, x)
	burst({ cf = hit * CFrame.new(0, 1.3, 0), tex = VT.impactBurst, color = ColorSequence.new(c2:Lerp(WHITE, 0.25), c1), size = NS(size, size * 1.4),
		life = NR(0.1, 0.14), n = 1, rot = NR(0, 0), z = 3, le = 0.6 })
	light(hit.Position + V(0, 2, 0), c1, 14 + size * 3, 3 + P.p, 0.25)
	kick(x, 0.05 + 0.04 * P.p)
end

---------------------------------------------------------------- slash (shared by every kit)
local SLASH = { crescent = VT.slash, thin = VT.slashThin, double = VT.slashDouble }
local function slashFrame(pos, mid, ahead)
	local m = mid.Unit
	local t = ahead - m * ahead:Dot(m)
	if t.Magnitude < 1e-3 then return nil end
	t = t.Unit
	local X = m * 0.588 + t * 0.809
	local Z = m * -0.809 + t * 0.588
	return CFrame.fromMatrix(pos, X, Z:Cross(X), Z) * CFrame.Angles(0, -math.pi / 2, 0)
end
K.slashFrame = slashFrame
local function swingSlash(center, tip, vel, c1, c2, style, scale, alpha)
	local mid = tip - center
	local cf = slashFrame(center, mid, vel)
	if not cf then return end
	local size = (mid.Magnitude + 1) * 2 / 0.86 * (scale or 1)
	local spin = CFrame.Angles(0, math.rad(-38 + rnd(-6, 6)), 0)
	local c, imgs = card(cf, size * 0.85, SLASH[style] or VT.slash, c1, alpha, 0.7, 3)
	tw(c, 0.3, { Size = V(size * 1.12, 0.05, size * 1.12), CFrame = cf * spin }, Enum.EasingStyle.Quart)
	fadeImgs(imgs, 0.28, 0.1)
	if style ~= "thin" and alpha < 0.5 then
		local c2p, imgs2 = card(cf, size * 0.78, SLASH[style] or VT.slash, c2:Lerp(WHITE, 0.55), alpha + 0.2, 0.6, 4)
		tw(c2p, 0.26, { Size = V(size * 1.03, 0.05, size * 1.03), CFrame = cf * spin }, Enum.EasingStyle.Quart)
		fadeImgs(imgs2, 0.18, 0.05)
	end
end
K.swingSlash = swingSlash

---------------------------------------------------------------- per-element kits
-- each: presence(S, x, P) once on equip (attach emitters to x.blade), tick(S, x, P) per frame (optional),
--       cut(S, x, P, tip) during the cutting frames, impacts[variant](hit, P, x)
local T = {}

-- STEEL: plain weapons. Clean slash, dust kicked up from the ground, rock chips, metal sparks.
T.steel = {
	slash = "thin",
	presence = function(S, x, P)
		if P.p >= 3 then table.insert(S.owned, emitter(x.blade, { Texture = VT.spark, Color = ColorSequence.new(P.hot), Size = seq(0, 0, 0.5, 0.35, 1, 0), Lifetime = NR(0.3, 0.5), Rate = 1.2, Speed = NR(0, 0), LightEmission = 1 })) end
	end,
	impacts = { function(hit, P, x)
		dustPuff(hit, 3 + P.p, 1.6 + 0.5 * P.p)
		debris(hit, 2 + P.p, P.p)
		sparks(hit * CFrame.new(0, 0.5, 0), P.c1, P.hot, 4 + 3 * P.p, 18)
		if P.p >= 2 then local r, im = card(hit * CFrame.new(0, 0.08, 0), 1.2, VT.shockRing, P.c1, 0.35, 0.6, 1.6); tw(r, 0.32, { Size = V(4 + 1.5 * P.p, 0.05, 4 + 1.5 * P.p) }, Enum.EasingStyle.Quart); fadeImgs(im, 0.22, 0.08) end
		if P.p >= 3 then flareStreak(hit.Position + V(0, 1.1, 0), P.hot, 5, 0.18) end
		kick(x, 0.03 + 0.015 * P.p)
	end },
}

-- FIRE
local function flameLick(cf, P, size, life)
	burst({ cf = cf, tex = VT.flame4x4, flip = true, color = cseq(0, P.hot, 0.35, P.c2, 0.7, P.c1, 1, P.dark), size = seq(0, size * 0.6, 0.4, size, 1, size * 0.7),
		trans = seq(0, 0.05, 0.8, 0.3, 1, 1), life = life or NR(0.45, 0.65), speed = NR(1, 3), spread = Vector2.new(8, 8), accel = V(0, 6, 0), n = 1, le = 0.85, rot = NR(-15, 15), rotation = NR(-10, 10) })
end
local function smokeRise(hit, P, n, size, col)
	for i = 1, n do
		burst({ cf = jitter(hit * CFrame.new(0, 1, 0), 1.2, 0), tex = VT.smoke4x4, flip = true, color = ColorSequence.new(col or C(70, 62, 60), C(40, 38, 38)), size = seq(0, size * 0.6, 1, size * 1.5),
			trans = seq(0, 0.55, 1, 1), life = NR(1.1, 1.6), speed = NR(1.5, 3.5), spread = Vector2.new(25, 25), accel = V(0, 1.8, 0), drag = 0.6, le = 0, n = 1, hold = 2.2, z = -2 })
	end
end
T.fire = {
	slash = "crescent",
	presence = function(S, x, P)
		table.insert(S.owned, emitter(x.blade, { Texture = VT.flame4x4, flip = true, Color = cseq(0, P.hot, 0.4, P.c2, 0.75, P.c1, 1, P.dark), Size = seq(0, 0.35, 0.4, 0.75 + 0.1 * P.p, 1, 0.2),
			Transparency = seq(0, 0.25, 1, 1), Lifetime = NR(0.35, 0.55), Rate = 8 + 5 * P.p, Speed = NR(0.2, 1), SpreadAngle = Vector2.new(15, 15), Acceleration = V(0, 5, 0), LightEmission = 0.9, RotSpeed = NR(-20, 20), Rotation = NR(-15, 15) }))
		table.insert(S.owned, emitter(x.blade, { Texture = VT.ember, Color = ColorSequence.new(P.hot, P.c1), Size = seq(0, 0.18, 1, 0), Lifetime = NR(0.8, 1.5), Rate = 3 + 2 * P.p, Speed = NR(0.5, 2), SpreadAngle = Vector2.new(180, 180), Acceleration = V(0, 2.5, 0), Drag = 0.6, LightEmission = 1 }))
	end,
	cut = function(S, x, P, tip) if x.t - (S.lastCutFx or 0) > 0.05 then S.lastCutFx = x.t; flameLick(CFrame.new(tip), P, 1 + 0.25 * P.p, NR(0.3, 0.45)) end end,
	impacts = {
		function(hit, P, x) -- Eruption: a column of fire bursts from the ground
			impactFrame(hit, P.c1, P.c2, 5, P, x)
			groundMark(hit, VT.scorch, C(25, 18, 15), 6 + P.p, 1.6, 0.05, 1)
			for i = 1, 4 + P.p do task.delay(i * 0.025, function() flameLick(jitter(hit * CFrame.new(0, 0.5 + i * 0.7, 0), 0.4, 0), P, 2.6 + P.p * 0.4 - i * 0.15) end) end
			for i = 1, 5 do flameLick(jitter(hit * CFrame.new(0, 0.3, 0), 2, 0), P, 1.6, NR(0.35, 0.5)) end
			sparks(hit * CFrame.new(0, 0.6, 0), P.c1, P.hot, 14 + 4 * P.p, 26)
			debris(hit, 3 + P.p, P.p, nil)
			smokeRise(hit, P, 3, 3 + P.p * 0.5)
		end,
		function(hit, P, x) -- Flame Ring: fire races outward in a ring
			impactFrame(hit, P.c1, P.c2, 4, P, x)
			groundMark(hit, VT.scorch, C(25, 18, 15), 8 + P.p, 1.4, 0.15, 1)
			local n = 10 + 2 * P.p
			for i = 1, n do
				local a = i / n * TAU + rnd(-0.12, 0.12)
				for k = 1, 3 do
					task.delay(k * 0.05, function() flameLick(hit * CFrame.Angles(0, a, 0) * CFrame.new(0, 0.4, -(1.2 + k * 1.3 + rnd(-0.3, 0.3))), P, 1.4 + 0.3 * P.p - k * 0.2, NR(0.35, 0.55)) end)
				end
			end
			sparks(hit * CFrame.new(0, 0.6, 0), P.c1, P.hot, 10 + 3 * P.p, 22)
			smokeRise(hit, P, 2, 3)
		end,
		function(hit, P, x) -- Fire Wave: a trail of fire bursts racing forward
			impactFrame(hit, P.c1, P.c2, 3.5, P, x)
			for i = 0, 5 + P.p do
				task.delay(i * 0.04, function()
					local at = hit * CFrame.new(rnd(-0.4, 0.4), 0, -i * 1.4)
					flameLick(at * CFrame.new(0, 0.6, 0), P, 2.2 + 0.25 * P.p - i * 0.12)
					groundMark(at, VT.scorch, C(25, 18, 15), 2.6, 1.2, 0.2, 1)
					if i % 2 == 0 then sparks(at * CFrame.new(0, 0.4, 0), P.c1, P.hot, 4, 16) end
				end)
			end
			smokeRise(hit * CFrame.new(0, 0, -3), P, 2, 3)
		end,
		function(hit, P, x) -- Meteor: a fireball drops out of the sky
			local s = 1.2 + 0.3 * P.p
			local m = part({ size = V(s, s, s), shape = Enum.PartType.Ball, color = P.hot, cf = hit * CFrame.new(6, 30, 8), life = 1 })
			local fe = emitter(m, { Texture = VT.flame4x4, flip = true, Color = cseq(0, P.hot, 0.4, P.c2, 1, P.c1), Size = seq(0, s * 1.6, 1, s * 0.6), Transparency = seq(0, 0.1, 1, 1), Lifetime = NR(0.25, 0.35), Rate = 90, Speed = NR(0, 1), LightEmission = 1 })
			tw(m, 0.32, { CFrame = hit * CFrame.new(0, s / 2, 0) }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
			task.delay(0.32, function()
				m:Destroy()
				impactFrame(hit, P.c1, P.c2, 7, P, x); kick(x, 0.12 + 0.04 * P.p)
				groundMark(hit, VT.scorch, C(20, 15, 12), 7 + P.p, 2, 0, 1)
				groundMark(hit, VT.cracks, P.c1, 6 + P.p, 1.1, 0.1, 2.2)
				burst({ cf = hit * CFrame.new(0, 1.4, 0), tex = VT.burst4x4, flip = true, color = cseq(0, P.c2, 0.4, P.c1, 1, P.dark), size = seq(0, 3, 1, 7 + P.p), trans = seq(0, 0.05, 1, 0.8), life = NR(0.5, 0.65), speed = NR(2, 5), n = 3, le = 0.55, z = 1 })
				debris(hit, 6 + P.p, P.p + 1)
				sparks(hit * CFrame.new(0, 0.6, 0), P.c1, P.hot, 22, 32)
				smokeRise(hit, P, 4, 4)
			end)
		end,
	},
}
T.dragon = { slash = "double", presence = T.fire.presence, cut = T.fire.cut, impacts = { T.fire.impacts[4], T.fire.impacts[1], T.fire.impacts[2], T.fire.impacts[3] } }

-- ICE
local function mist(hit, P, n, size)
	for i = 1, n do
		burst({ cf = jitter(hit * CFrame.new(0, 0.6, 0), 1.5, 0), tex = VT.smoke4x4, flip = true, color = ColorSequence.new(P.hot, P.c1), size = seq(0, size * 0.5, 1, size * 1.4),
			trans = seq(0, 0.5, 1, 1), life = NR(1, 1.5), speed = NR(1, 3), spread = Vector2.new(70, 70), accel = V(0, -0.4, 0), drag = 1.2, le = 0.25, n = 1, hold = 2, z = -1 })
	end
end
local function iceSpike(at, P, h)
	burst({ cf = at * CFrame.new(0, h * 0.45, 0), tex = VT.shard, color = ColorSequence.new(P.hot:Lerp(P.c1, 0.3)), size = seq(0, h * 0.3, 0.12, h, 0.85, h, 1, h * 0.6), trans = seq(0, 0.1, 0.8, 0.15, 1, 1),
		life = NR(1.1, 1.3), n = 1, orient = Enum.ParticleOrientation.FacingCameraWorldUp, rot = NR(0, 0), rotation = NR(-12, 12), le = 0.55, hold = 1.6 })
end
T.ice = {
	slash = "thin",
	presence = function(S, x, P)
		table.insert(S.owned, emitter(x.blade, { Texture = VT.smoke4x4, flip = true, Color = ColorSequence.new(P.hot, P.c1), Size = seq(0, 0.5, 1, 1.4), Transparency = seq(0, 0.8, 1, 1), Lifetime = NR(0.9, 1.3), Rate = 3 + P.p, Speed = NR(0.1, 0.4), Acceleration = V(0, -1.2, 0), LightEmission = 0.3 }))
		table.insert(S.owned, emitter(x.blade, { Texture = VT.spark, Color = ColorSequence.new(WHITE, P.c1), Size = seq(0, 0, 0.3, 0.22, 1, 0), Lifetime = NR(0.5, 0.9), Rate = 3 + 2 * P.p, Speed = NR(0, 0.3), LightEmission = 1 }))
	end,
	cut = function(S, x, P, tip)
		if x.t - (S.lastCutFx or 0) > 0.06 then S.lastCutFx = x.t
			burst({ cf = CFrame.new(tip), tex = VT.shard, color = ColorSequence.new(P.hot), size = NS(0.45, 0.1), life = NR(0.3, 0.5), speed = NR(2, 5), accel = V(0, -18, 0), n = 2, le = 0.5, rot = NR(-200, 200) })
		end
	end,
	impacts = {
		function(hit, P, x) -- Frost Bloom: a crystal of frost spreads across the ground
			impactFrame(hit, P.c1, P.c2, 4, P, x)
			local c, im = groundMark(hit, VT.frost, P.hot:Lerp(P.c1, 0.4), 7 + P.p, 1.8, 0, 1.6)
			burst({ cf = hit * CFrame.new(0, 0.5, 0), tex = VT.shard, color = ColorSequence.new(P.hot, P.c1), size = NS(0.8, 0.2), orient = Enum.ParticleOrientation.VelocityParallel, life = NR(0.35, 0.6), speed = NR(14, 24), spread = Vector2.new(75, 75), accel = V(0, -40, 0), drag = 2, n = 12 + 3 * P.p, le = 0.5 })
			mist(hit, P, 3, 3)
		end,
		function(hit, P, x) -- Ice Spikes: a line of spikes punches up out of the ground
			impactFrame(hit, P.c1, P.c2, 3.5, P, x)
			for i = 0, 4 + P.p do
				task.delay(i * 0.05, function()
					local at = hit * CFrame.new(rnd(-0.5, 0.5), 0, -i * 1.3)
					iceSpike(at, P, 1.8 + i * 0.35 + 0.4 * P.p)
					groundMark(at, VT.frost, P.hot:Lerp(P.c1, 0.4), 2.8, 1.2, 0.2, 1.4)
					sparks(at * CFrame.new(0, 0.3, 0), P.c1, WHITE, 3, 12, 0.35)
				end)
			end
			mist(hit * CFrame.new(0, 0, -3), P, 2, 3)
		end,
		function(hit, P, x) -- Shatter: the ground ices over and bursts into glass
			impactFrame(hit, P.c1, P.c2, 5, P, x)
			groundMark(hit, VT.frost, P.hot:Lerp(P.c1, 0.4), 6 + P.p, 1.2, 0.05, 1.6)
			for i = 1, 5 + P.p do iceSpike(jitter(hit, 1.6, 0), P, rnd(1.2, 2.2)) end
			task.delay(0.35, function() debris(hit, 7 + P.p, P.p + 1, P.hot:Lerp(P.c1, 0.35), Enum.Material.Glass); sparks(hit * CFrame.new(0, 0.8, 0), P.c1, WHITE, 16, 24) end)
			mist(hit, P, 2, 3)
		end,
		function(hit, P, x) -- Blizzard: a whirl of snow and frost
			impactFrame(hit, P.c1, P.c2, 3.5, P, x)
			local s, im = card(hit * CFrame.new(0, 0.12, 0), 3, VT.swirl, P.hot, 0.1, 1.4, 2)
			tw(s, 0.9, { Size = V(10 + P.p, 0.05, 10 + P.p), CFrame = hit * CFrame.new(0, 0.12, 0) * CFrame.Angles(0, -5, 0) }, Enum.EasingStyle.Quart); fadeImgs(im, 0.5, 0.45)
			groundMark(hit, VT.frost, P.hot:Lerp(P.c1, 0.4), 6, 1.4, 0.15, 1.4)
			burst({ cf = hit * CFrame.new(0, 1, 0), tex = VT.ember, color = ColorSequence.new(WHITE), size = NS(0.25, 0.1), life = NR(0.8, 1.4), speed = NR(6, 12), spread = Vector2.new(85, 85), accel = V(0, -4, 0), drag = 1.5, n = 30, le = 0.7 })
			mist(hit, P, 4, 3.5)
		end,
	},
}

-- LIGHTNING
local function bolt(from, to, P, width, life)
	beam(from, to, VT.lightning, P.hot, width, life, { flicker = true, hold = life * 0.35 })
	beam(from, to, VT.lightning, P.c1, width * 2.4, life * 0.8, { flicker = true, trans = 0.35 })
end
T.lightning = {
	slash = "double",
	presence = function(S, x, P)
		table.insert(S.owned, emitter(x.blade, { Texture = VT.electric4x4, flip = true, Color = ColorSequence.new(P.hot, P.c1), Size = NS(1.2 + 0.2 * P.p, 1.6 + 0.3 * P.p), Lifetime = NR(0.18, 0.26), Rate = 2 + 1.5 * P.p, Speed = NR(0, 0), LightEmission = 1, RotSpeed = NR(0, 0) }))
		table.insert(S.owned, emitter(x.blade, { Texture = VT.sparkStreak, Orientation = Enum.ParticleOrientation.VelocityParallel, Color = ColorSequence.new(P.hot, P.c1), Size = NS(0.25, 0), Lifetime = NR(0.1, 0.2), Rate = 3 + 2 * P.p, Speed = NR(4, 8), SpreadAngle = Vector2.new(180, 180), LightEmission = 1 }))
	end,
	cut = function(S, x, P, tip)
		if x.t - (S.lastCutFx or 0) > 0.07 then S.lastCutFx = x.t
			burst({ cf = CFrame.new(tip), tex = VT.electric4x4, flip = true, color = ColorSequence.new(P.hot, P.c1), size = NS(1.6, 2.2), life = NR(0.15, 0.22), n = 1, le = 1 })
		end
	end,
	impacts = {
		function(hit, P, x) -- Thunder Strike: a bolt from the sky
			local top = hit.Position + V(rnd(-4, 4), 34, rnd(-4, 4))
			bolt(top, hit.Position, P, 1.4 + 0.25 * P.p, 0.32)
			impactFrame(hit, P.c1, P.c2, 6, P, x); kick(x, 0.1 + 0.04 * P.p)
			local l = light(hit.Position + V(0, 3, 0), P.c1, 40, 8, 0.4)
			task.delay(0.06, function() if l.Parent then l.Brightness = 1 end end); task.delay(0.1, function() if l.Parent then l.Brightness = 7 end end)
			groundMark(hit, VT.scorch, C(20, 20, 26), 5 + P.p, 1.6, 0.05, 1)
			groundMark(hit, VT.cracks, P.c1, 5 + P.p, 0.7, 0.15, 2.4)
			burst({ cf = hit * CFrame.new(0, 0.8, 0), tex = VT.electric4x4, flip = true, color = ColorSequence.new(P.hot, P.c1), size = NS(5, 7), life = NR(0.25, 0.32), n = 2, le = 1 })
			sparks(hit * CFrame.new(0, 0.6, 0), P.c1, P.hot, 18 + 4 * P.p, 30)
			debris(hit, 3 + P.p, P.p)
		end,
		function(hit, P, x) -- Chain Arc: lightning jumps between points on the ground
			impactFrame(hit, P.c1, P.c2, 4, P, x)
			local n = 5 + math.floor(P.p)
			local prev = hit.Position + V(0, 0.6, 0)
			for i = 1, n do
				task.delay(i * 0.045, function()
					local pt = (hit * CFrame.Angles(0, i * 2.4 + rnd(-0.3, 0.3), 0) * CFrame.new(0, 0.5, -rnd(2.5, 4.5))).Position
					bolt(prev, pt, P, 0.8, 0.22)
					burst({ cf = CFrame.new(pt), tex = VT.electric4x4, flip = true, color = ColorSequence.new(P.hot, P.c1), size = NS(2.2, 3), life = NR(0.2, 0.25), n = 1, le = 1 })
					groundMark(CFrame.new(pt - V(0, 0.5, 0)), VT.scorch, C(20, 20, 26), 1.8, 1.2, 0.2, 1)
					prev = pt
				end)
			end
			sparks(hit * CFrame.new(0, 0.6, 0), P.c1, P.hot, 12, 24)
		end,
		function(hit, P, x) -- Static Field: the area crackles with live current
			impactFrame(hit, P.c1, P.c2, 3.5, P, x)
			local r, im = card(hit * CFrame.new(0, 0.08, 0), 2, VT.ringDashed, P.c1, 0, 1.1, 2.6)
			tw(r, 0.35, { Size = V(9 + P.p, 0.05, 9 + P.p), CFrame = hit * CFrame.new(0, 0.08, 0) * CFrame.Angles(0, 1, 0) }, Enum.EasingStyle.Quart); fadeImgs(im, 0.4, 0.5)
			for i = 1, 8 + 2 * P.p do
				task.delay(rnd(0, 0.5), function() burst({ cf = jitter(hit * CFrame.new(0, 0.4, 0), 3.5, 0), tex = VT.electric4x4, flip = true, color = ColorSequence.new(P.hot, P.c1), size = NS(1.5, 2.4), life = NR(0.16, 0.22), n = 1, le = 1 }) end)
			end
			sparks(hit * CFrame.new(0, 0.5, 0), P.c1, P.hot, 10, 18)
		end,
		function(hit, P, x) -- Storm Nova: bolts fork outward from the point of impact
			impactFrame(hit, P.c1, P.c2, 5, P, x); kick(x, 0.08 + 0.03 * P.p)
			local c0 = hit.Position + V(0, 0.8, 0)
			for i = 1, 6 + P.p do
				local a = i / (6 + P.p) * TAU + rnd(-0.2, 0.2)
				local pt = c0 + V(math.cos(a), rnd(-0.1, 0.25), math.sin(a)) * rnd(4.5, 6.5)
				bolt(c0, pt, P, 0.7, 0.24)
			end
			local r, im = card(hit * CFrame.new(0, 0.1, 0), 2, VT.shockRing, P.c1, 0, 0.8, 3)
			tw(r, 0.32, { Size = V(13 + P.p, 0.05, 13 + P.p) }, Enum.EasingStyle.Quart); fadeImgs(im, 0.25, 0.08)
			groundMark(hit, VT.scorch, C(20, 20, 26), 4 + P.p, 1.2, 0.1, 1)
		end,
	},
}

-- NATURE (and PETAL: the same kit with blossom colours)
local function leafBurst(hit, P, n, speed, up)
	burst({ cf = hit * CFrame.new(0, 0.6, 0), tex = VT.leaf, color = ColorSequence.new(P.c1, P.c2), size = NS(0.55, 0.4), life = NR(1, 1.6), speed = NR(speed * 0.5, speed),
		spread = Vector2.new(80, 80), accel = V(0, up or -6, 0), drag = 2.2, n = n, le = 0.05, rot = NR(-260, 260), hold = 2.2 })
end
T.nature = {
	slash = "double",
	presence = function(S, x, P)
		table.insert(S.owned, emitter(x.blade, { Texture = VT.leaf, Color = ColorSequence.new(P.c1, P.c2), Size = NS(0.32, 0.25), Lifetime = NR(1.4, 2.2), Rate = 1.2 + P.p * 0.8, Speed = NR(0.3, 1), SpreadAngle = Vector2.new(180, 180), Acceleration = V(0.6, -2, 0), Drag = 1, RotSpeed = NR(-120, 120), LightEmission = 0.05 }))
		table.insert(S.owned, emitter(x.blade, { Texture = VT.ember, Color = ColorSequence.new(P.hot), Size = seq(0, 0, 0.3, 0.14, 1, 0), Lifetime = NR(1, 1.8), Rate = 2 + P.p, Speed = NR(0.1, 0.5), Acceleration = V(0, 0.6, 0), LightEmission = 1 }))
	end,
	cut = function(S, x, P, tip) if x.t - (S.lastCutFx or 0) > 0.08 then S.lastCutFx = x.t; burst({ cf = CFrame.new(tip), tex = VT.leaf, color = ColorSequence.new(P.c1, P.c2), size = NS(0.4, 0.3), life = NR(0.6, 1), speed = NR(1, 3), accel = V(0, -4, 0), drag = 2, n = 2, le = 0.05, rot = NR(-200, 200) }) end end,
	impacts = {
		function(hit, P, x) -- Overgrowth: earth bursts open, leaves fly
			impactFrame(hit, P.c1, P.c2, 3.5, P, x)
			dustPuff(hit, 5, 2.2)
			groundMark(hit, VT.cracks, P.dark, 6 + P.p, 1.6, 0.1, 1)
			debris(hit, 4 + P.p, P.p)
			leafBurst(hit, P, 16 + 4 * P.p, 16)
		end,
		function(hit, P, x) -- Thorn Ring: thorns punch up in a ring
			impactFrame(hit, P.c1, P.c2, 3.5, P, x)
			local n = 7 + P.p
			for i = 1, n do
				task.delay(i * 0.025, function()
					local at = hit * CFrame.Angles(0, i / n * TAU + rnd(-0.15, 0.15), 0) * CFrame.new(0, 0, -rnd(2.2, 3))
					burst({ cf = at * CFrame.new(0, 0.9, 0), tex = VT.shard, color = ColorSequence.new(P.dark:Lerp(P.c1, 0.5)), size = seq(0, 0.4, 0.1, 2 + 0.3 * P.p, 0.85, 2 + 0.3 * P.p, 1, 0.8), trans = seq(0, 0, 0.85, 0.05, 1, 1),
						life = NR(1, 1.2), n = 1, orient = Enum.ParticleOrientation.FacingCameraWorldUp, rot = NR(0, 0), rotation = NR(-18, 18), le = 0.05, hold = 1.5 })
					dustPuff(at, 1, 1.2)
				end)
			end
			leafBurst(hit, P, 10, 10)
		end,
		function(hit, P, x) -- Bloom: a spiral of leaves and pollen rises
			impactFrame(hit, P.c1, P.c2, 3, P, x)
			local s, im = card(hit * CFrame.new(0, 0.1, 0), 2.5, VT.swirl, P.c1, 0.15, 1.4, 1.6)
			tw(s, 1, { Size = V(9 + P.p, 0.05, 9 + P.p), CFrame = hit * CFrame.new(0, 0.1, 0) * CFrame.Angles(0, 4, 0) }, Enum.EasingStyle.Quart); fadeImgs(im, 0.5, 0.5)
			leafBurst(hit, P, 18 + 4 * P.p, 9, 3)
			burst({ cf = hit * CFrame.new(0, 0.5, 0), tex = VT.ember, color = ColorSequence.new(P.hot), size = NS(0.25, 0), life = NR(1.2, 2), speed = NR(2, 6), spread = Vector2.new(60, 60), accel = V(0, 2, 0), drag = 1, n = 22, le = 1 })
		end,
		function(hit, P, x) -- Earthquake: the ground cracks and heaves
			impactFrame(hit, P.c1, P.c2, 3, P, x); kick(x, 0.14 + 0.04 * P.p)
			groundMark(hit, VT.cracks, P.dark, 9 + P.p, 1.8, 0, 1)
			dustPuff(hit, 7, 2.8)
			debris(hit, 8 + P.p, P.p + 1)
			task.delay(0.12, function() dustPuff(hit * CFrame.new(0, 0, -3), 4, 2) end)
			leafBurst(hit, P, 8, 8)
		end,
	},
}
T.petal = { slash = "thin", presence = T.nature.presence, cut = T.nature.cut, impacts = { T.nature.impacts[3], T.nature.impacts[1], T.nature.impacts[2], T.nature.impacts[3] } }

-- ARCANE
local function runeSeal(hit, P, size, life, spin, tex)
	local cf = hit * CFrame.new(0, 0.1, 0) * CFrame.Angles(0, rnd(0, TAU), 0)
	local c, im = card(cf, size * 0.3, tex or VT.runeRing, P.c1, 0, life + 0.2, 2.6)
	tw(c, 0.25, { Size = V(size, 0.05, size) }, Enum.EasingStyle.Back)
	tw(c, life, { CFrame = cf * CFrame.Angles(0, spin, 0) }, Enum.EasingStyle.Sine)
	fadeImgs(im, life * 0.45, life * 0.55)
	return c
end
T.arcane = {
	slash = "double",
	presence = function(S, x, P)
		table.insert(S.owned, emitter(x.blade, { Texture = VT.ember, Color = ColorSequence.new(P.hot, P.c1), Size = seq(0, 0, 0.3, 0.2, 1, 0), Lifetime = NR(1, 1.6), Rate = 3 + 2 * P.p, Speed = NR(0.2, 0.8), SpreadAngle = Vector2.new(180, 180), Acceleration = V(0, 1.2, 0), Drag = 0.8, LightEmission = 1 }))
		S.rune = card(CFrame.new(), 1.2 + 0.25 * P.p, VT.runeRing, P.c1, 0.35, nil, 2, S.folder)
	end,
	tick = function(S, x, P)
		if S.rune then S.rune.CFrame = x.blade.CFrame * CFrame.new(0, -x.blade.Size.Y * 0.35, 0) * CFrame.Angles(0, x.t * 1.3, 0) end
	end,
	cut = function(S, x, P, tip) if x.t - (S.lastCutFx or 0) > 0.05 then S.lastCutFx = x.t; burst({ cf = CFrame.new(tip), tex = VT.spark, color = ColorSequence.new(P.hot, P.c1), size = NS(0.6, 0), life = NR(0.25, 0.4), n = 2, le = 1, rot = NR(0, 0) }) end end,
	impacts = {
		function(hit, P, x) -- Rune Seal: a seal stamps the ground and releases its power
			impactFrame(hit, P.c1, P.c2, 3.5, P, x)
			runeSeal(hit, P, 7 + P.p, 1.3, 1.4)
			runeSeal(hit, P, 4 + 0.5 * P.p, 1.1, -2.2, VT.magicCircle)
			burst({ cf = hit * CFrame.new(0, 0.3, 0), tex = VT.ember, color = ColorSequence.new(P.hot, P.c1), size = NS(0.35, 0), life = NR(0.9, 1.4), speed = NR(2, 5), spread = Vector2.new(25, 25), accel = V(0, 6, 0), n = 20 + 4 * P.p, le = 1 })
		end,
		function(hit, P, x) -- Arcane Burst: a ring of force and scattering motes
			impactFrame(hit, P.c1, P.c2, 5, P, x)
			flareStreak(hit.Position + V(0, 1.3, 0), P.c2, 9, 0.25)
			local r, im = card(hit * CFrame.new(0, 0.1, 0), 2, VT.ringDashed, P.c1, 0, 0.8, 3)
			tw(r, 0.38, { Size = V(12 + P.p, 0.05, 12 + P.p), CFrame = hit * CFrame.new(0, 0.1, 0) * CFrame.Angles(0, 1.4, 0) }, Enum.EasingStyle.Quart); fadeImgs(im, 0.25, 0.12)
			burst({ cf = hit * CFrame.new(0, 1, 0), tex = VT.spark, color = ColorSequence.new(P.hot, P.c1), size = NS(0.6, 0), life = NR(0.4, 0.7), speed = NR(10, 18), drag = 3, n = 18 + 4 * P.p, le = 1 })
		end,
		function(hit, P, x) -- Spell Pillar: a beam of light answers from above
			impactFrame(hit, P.c1, P.c2, 3.5, P, x)
			runeSeal(hit, P, 5 + P.p, 1, 1.2)
			beam(hit.Position, hit.Position + V(0, 22, 0), VT.energyTrail, P.c2, 2.2 + 0.3 * P.p, 0.55, { width1 = 0.4, hold = 0.15 })
			beam(hit.Position, hit.Position + V(0, 22, 0), VT.energyTrail, WHITE, 0.8, 0.4, { width1 = 0.2, hold = 0.1 })
			burst({ cf = hit * CFrame.new(0, 0.3, 0), tex = VT.ember, color = ColorSequence.new(P.hot), size = NS(0.3, 0), life = NR(0.8, 1.2), speed = NR(4, 9), spread = Vector2.new(12, 12), n = 16, le = 1 })
		end,
		function(hit, P, x) -- Glyph Rain: small seals drop onto the area
			impactFrame(hit, P.c1, P.c2, 3, P, x)
			for i = 1, 4 + P.p do
				task.delay(i * 0.07, function()
					local at = jitter(hit, 3.5, 0)
					local c = runeSeal(at, P, rnd(2.2, 3.2), 0.8, rnd(-2, 2))
					burst({ cf = at * CFrame.new(0, 0.3, 0), tex = VT.spark, color = ColorSequence.new(P.hot, P.c1), size = NS(1, 0), life = NR(0.2, 0.3), n = 1, le = 1, rot = NR(0, 0) })
				end)
			end
		end,
	},
}

-- VOID
local function darkSmoke(hit, P, n, size)
	for i = 1, n do
		burst({ cf = jitter(hit * CFrame.new(0, 0.8, 0), 1.4, 0), tex = VT.smoke4x4, flip = true, color = ColorSequence.new(P.dark, BLACK), size = seq(0, size * 0.5, 1, size * 1.4), trans = seq(0, 0.25, 1, 1),
			life = NR(0.9, 1.4), speed = NR(1, 3), spread = Vector2.new(60, 60), accel = V(0, 1, 0), drag = 1, le = 0, n = 1, hold = 2, z = -1 })
	end
end
T.void = {
	slash = "crescent",
	presence = function(S, x, P)
		table.insert(S.owned, emitter(x.blade, { Texture = VT.smoke4x4, flip = true, Color = ColorSequence.new(P.dark, BLACK), Size = seq(0, 0.4, 1, 1.2), Transparency = seq(0, 0.45, 1, 1), Lifetime = NR(0.7, 1.1), Rate = 4 + 2 * P.p, Speed = NR(0.2, 0.6), Acceleration = V(0, 1, 0), LightEmission = 0 }))
		table.insert(S.owned, emitter(x.blade, { Texture = VT.ember, Color = ColorSequence.new(P.c2), Size = seq(0, 0, 0.3, 0.16, 1, 0), Lifetime = NR(0.6, 1), Rate = 3 + P.p, Speed = NR(-1.5, -0.5), SpreadAngle = Vector2.new(180, 180), LightEmission = 1 }))
	end,
	cut = function(S, x, P, tip) if x.t - (S.lastCutFx or 0) > 0.05 then S.lastCutFx = x.t; burst({ cf = CFrame.new(tip), tex = VT.smoke4x4, flip = true, color = ColorSequence.new(P.dark, BLACK), size = NS(1, 1.8), trans = seq(0, 0.3, 1, 1), life = NR(0.4, 0.6), n = 1, le = 0 }) end end,
	impacts = {
		function(hit, P, x) -- Collapse: space folds into a point, then snaps back
			local cf = hit * CFrame.new(0, 0.12, 0)
			local s, im = card(cf, 11 + P.p, VT.swirl, P.dark:Lerp(P.c1, 0.4), 0.1, 1, 2)
			tw(s, 0.32, { Size = V(1, 0.05, 1), CFrame = cf * CFrame.Angles(0, 6, 0) }, Enum.EasingStyle.Quart, Enum.EasingDirection.In)
			task.delay(0.32, function()
				impactFrame(hit, P.c1, P.c2, 5, P, x); kick(x, 0.1 + 0.03 * P.p)
				local r, im2 = card(cf, 1, VT.shockRing, P.c2, 0, 0.8, 3)
				tw(r, 0.35, { Size = V(13 + P.p, 0.05, 13 + P.p) }, Enum.EasingStyle.Quart); fadeImgs(im2, 0.25, 0.1)
				darkSmoke(hit, P, 4, 3)
			end)
		end,
		function(hit, P, x) -- Rift: a tear hangs in the air
			impactFrame(hit, P.c1, P.c2, 3.5, P, x)
			local cf = hit * CFrame.new(0, 2.4, 0) * CFrame.Angles(math.rad(90), 0, math.rad(rnd(-25, 25)))
			local c, im = card(cf, 1, VT.slashThin, P.c2, 0, 1.2, 3.5)
			tw(c, 0.18, { Size = V(7 + P.p, 0.05, 7 + P.p) }, Enum.EasingStyle.Back); fadeImgs(im, 0.45, 0.6)
			darkSmoke(hit * CFrame.new(0, 1.5, 0), P, 4, 2.5)
			burst({ cf = hit * CFrame.new(0, 2.4, 0), tex = VT.ember, color = ColorSequence.new(P.c2), size = NS(0.3, 0), life = NR(0.5, 0.9), speed = NR(4, 9), drag = 2, n = 16, le = 1 })
		end,
		function(hit, P, x) -- Event Horizon: a black sphere swallows the light
			impactFrame(hit, P.c1, P.c2, 3, P, x)
			local s = 3.5 + 0.5 * P.p
			local orb = part({ shape = Enum.PartType.Ball, size = V(0.5, 0.5, 0.5), cf = hit * CFrame.new(0, 1.8, 0), color = BLACK, mat = Enum.Material.SmoothPlastic, life = 1.2 })
			tw(orb, 0.2, { Size = V(s, s, s) }, Enum.EasingStyle.Back)
			burst({ cf = hit * CFrame.new(0, 1.8, 0), tex = VT.bubble, color = ColorSequence.new(P.c2), size = seq(0, s * 1.25, 1, s * 1.1), trans = seq(0, 0.1, 1, 1), life = NR(0.75, 0.75), n = 1, le = 1, rot = NR(0, 0), hold = 1 })
			task.delay(0.65, function() tw(orb, 0.2, { Size = V(0.1, 0.1, 0.1) }, Enum.EasingStyle.Back, Enum.EasingDirection.In) end)
			task.delay(0.85, function() burst({ cf = hit * CFrame.new(0, 1.8, 0), tex = VT.spark, color = ColorSequence.new(WHITE, P.c2), size = NS(0.6, 0), life = NR(0.3, 0.5), speed = NR(12, 20), n = 20, le = 1 }); light(hit.Position + V(0, 2, 0), P.c2, 20, 6, 0.3) end)
		end,
		function(hit, P, x) -- Abyssal Wave: dark ripples roll outward
			impactFrame(hit, P.c1, P.c2, 3.5, P, x)
			for i = 0, 2 do
				task.delay(i * 0.12, function()
					local r, im = card(hit * CFrame.new(0, 0.1 + i * 0.01, 0), 1.5, VT.ripple, P.c1, 0, 0.9, 2.6)
					tw(r, 0.5, { Size = V(11 + 2 * i + P.p, 0.05, 11 + 2 * i + P.p) }, Enum.EasingStyle.Quart); fadeImgs(im, 0.3, 0.2)
				end)
			end
			darkSmoke(hit, P, 3, 2.5)
		end,
	},
}

-- HOLY
T.holy = {
	slash = "crescent",
	presence = function(S, x, P)
		table.insert(S.owned, emitter(x.blade, { Texture = VT.ember, Color = ColorSequence.new(P.hot, P.c1), Size = seq(0, 0, 0.3, 0.22, 1, 0), Lifetime = NR(1, 1.6), Rate = 3 + 2 * P.p, Speed = NR(0.3, 0.9), SpreadAngle = Vector2.new(30, 30), Acceleration = V(0, 2.2, 0), LightEmission = 1 }))
		table.insert(S.owned, emitter(x.blade, { Texture = VT.glow, Color = ColorSequence.new(P.c1), Size = NS(2.2 + 0.4 * P.p), Transparency = seq(0, 1, 0.5, 0.85, 1, 1), Lifetime = NR(0.8, 1.1), Rate = 2.5, Speed = NR(0, 0), LightEmission = 1 }))
	end,
	cut = function(S, x, P, tip) if x.t - (S.lastCutFx or 0) > 0.06 then S.lastCutFx = x.t; burst({ cf = CFrame.new(tip), tex = VT.spark, color = ColorSequence.new(WHITE, P.c1), size = NS(0.7, 0), life = NR(0.25, 0.4), n = 1, le = 1, rot = NR(0, 0) }) end end,
	impacts = {
		function(hit, P, x) -- Judgement: a column of light from the heavens
			beam(hit.Position + V(0, 26, 0), hit.Position, VT.energyTrail, P.c1, 3 + 0.4 * P.p, 0.6, { hold = 0.2 })
			beam(hit.Position + V(0, 26, 0), hit.Position, VT.energyTrail, WHITE, 1.2, 0.45, { hold = 0.15 })
			impactFrame(hit, P.c1, P.c2, 5, P, x)
			burst({ cf = hit * CFrame.new(0, 1.4, 0), tex = VT.lightRays, color = ColorSequence.new(P.hot), size = NS(7 + P.p, 10 + P.p), life = NR(0.35, 0.45), n = 1, le = 0.8, rot = NR(10, 20) })
			groundMark(hit, VT.runeRing, P.c1, 6 + P.p, 0.8, 0.1, 2)
			burst({ cf = hit * CFrame.new(0, 0.3, 0), tex = VT.ember, color = ColorSequence.new(P.hot), size = NS(0.3, 0), life = NR(1, 1.6), speed = NR(2, 5), spread = Vector2.new(30, 30), accel = V(0, 4, 0), n = 20, le = 1 })
		end,
		function(hit, P, x) -- Halo: a ring of light settles and lifts away
			impactFrame(hit, P.c1, P.c2, 4, P, x)
			local cf = hit * CFrame.new(0, 0.15, 0)
			local h, im = card(cf, 2, VT.shockRing, P.hot, 0, 1.2, 3)
			tw(h, 0.3, { Size = V(7 + P.p, 0.05, 7 + P.p) }, Enum.EasingStyle.Quart)
			tw(h, 0.9, { CFrame = cf * CFrame.new(0, 3, 0) }, Enum.EasingStyle.Sine); fadeImgs(im, 0.5, 0.4)
			burst({ cf = hit * CFrame.new(0, 1.2, 0), tex = VT.lightRays, color = ColorSequence.new(P.hot), size = NS(6, 8), life = NR(0.3, 0.4), n = 1, le = 0.8 })
			sparks(hit * CFrame.new(0, 0.5, 0), P.c1, WHITE, 10, 16)
		end,
		function(hit, P, x) -- Radiance: a burst of god-rays and a blinding streak
			impactFrame(hit, P.c1, P.c2, 6, P, x)
			burst({ cf = hit * CFrame.new(0, 1.4, 0), tex = VT.lightRays, color = ColorSequence.new(WHITE, P.c1), size = NS(9 + P.p, 13 + P.p), life = NR(0.4, 0.5), n = 2, le = 0.8, rot = NR(-25, 25) })
			flareStreak(hit.Position + V(0, 1.4, 0), P.hot, 12, 0.3)
			groundMark(hit, VT.magicCircle, P.c1, 5 + P.p, 0.6, 0.2, 2)
		end,
	},
}
T.solar = { slash = "crescent", presence = T.holy.presence, cut = T.fire.cut, impacts = {
	function(hit, P, x) T.holy.impacts[3](hit, P, x); for i = 1, 4 do flameLick(jitter(hit * CFrame.new(0, 0.4, 0), 1.6, 0), P, 1.6) end end,
	function(hit, P, x) T.holy.impacts[1](hit, P, x); groundMark(hit, VT.scorch, C(30, 22, 12), 4, 1.2, 0.3, 1) end,
	function(hit, P, x) T.holy.impacts[2](hit, P, x); sparks(hit * CFrame.new(0, 0.6, 0), P.c1, P.hot, 14, 22) end,
} }

-- BLOOD
local function droplets(hit, P, n, speed)
	burst({ cf = hit * CFrame.new(0, 0.6, 0), tex = VT.ember, color = ColorSequence.new(P.c1, P.dark), size = NS(0.32, 0.18), life = NR(0.5, 0.9), speed = NR(speed * 0.5, speed), spread = Vector2.new(65, 65), accel = V(0, -55, 0), n = n, le = 0.15 })
end
T.blood = {
	slash = "crescent",
	presence = function(S, x, P)
		table.insert(S.owned, emitter(x.blade, { Texture = VT.smoke4x4, flip = true, Color = ColorSequence.new(P.c1, P.dark), Size = seq(0, 0.4, 1, 1.1), Transparency = seq(0, 0.65, 1, 1), Lifetime = NR(0.8, 1.2), Rate = 2 + P.p, Speed = NR(0.1, 0.4), Acceleration = V(0, -0.6, 0), LightEmission = 0.1 }))
		table.insert(S.owned, emitter(x.blade, { Texture = VT.ember, Color = ColorSequence.new(P.c1), Size = NS(0.12, 0.08), Lifetime = NR(0.5, 0.8), Rate = 2 + P.p, Speed = NR(0, 0.2), Acceleration = V(0, -14, 0), LightEmission = 0.2 }))
	end,
	cut = function(S, x, P, tip) if x.t - (S.lastCutFx or 0) > 0.05 then S.lastCutFx = x.t; burst({ cf = CFrame.new(tip), tex = VT.ember, color = ColorSequence.new(P.c1), size = NS(0.2, 0.1), life = NR(0.4, 0.6), speed = NR(2, 5), accel = V(0, -40, 0), n = 3, le = 0.15 }) end end,
	impacts = {
		function(hit, P, x) -- Crimson Splash
			impactFrame(hit, P.c1, P.c2, 3.5, P, x)
			groundMark(hit, VT.splat, P.dark, 5 + P.p, 1.8, 0.05, 1)
			droplets(hit, P, 22 + 4 * P.p, 18)
			burst({ cf = hit * CFrame.new(0, 0.6, 0), tex = VT.smoke4x4, flip = true, color = ColorSequence.new(P.c1, P.dark), size = seq(0, 1.5, 1, 4), trans = seq(0, 0.45, 1, 1), life = NR(0.7, 1), speed = NR(2, 4), n = 3, le = 0.1 })
		end,
		function(hit, P, x) -- Rending: two crossing gashes torn in the ground
			impactFrame(hit, P.c1, P.c2, 3.5, P, x)
			for k = -1, 1, 2 do
				local cf = hit * CFrame.new(0, 0.08, 0) * CFrame.Angles(0, math.rad(45 * k + rnd(-10, 10)), 0)
				local c, im = card(cf, 1, VT.slashThin, P.c1, 0, 1.6, 2)
				tw(c, 0.12, { Size = V(7 + P.p, 0.05, 7 + P.p) }, Enum.EasingStyle.Quart); fadeImgs(im, 0.8, 0.7)
			end
			droplets(hit, P, 16, 14)
			groundMark(hit, VT.splat, P.dark, 3.5, 1.4, 0.25, 1)
		end,
		function(hit, P, x) -- Blood Moon: a crimson seal pulses and erupts
			impactFrame(hit, P.c1, P.c2, 4, P, x)
			local c = runeSeal(hit, P, 6 + P.p, 1.2, -1.6)
			task.delay(0.3, function() droplets(hit, P, 26, 20); light(hit.Position + V(0, 2, 0), P.c1, 20, 5, 0.3) end)
		end,
	},
}

-- TOXIC
T.toxic = {
	slash = "swirl",
	presence = function(S, x, P)
		table.insert(S.owned, emitter(x.blade, { Texture = VT.bubble, Color = ColorSequence.new(P.hot, P.c1), Size = seq(0, 0.1, 0.8, 0.3, 1, 0.38), Transparency = seq(0, 0.1, 0.9, 0.2, 1, 1), Lifetime = NR(0.8, 1.3), Rate = 3 + 2 * P.p, Speed = NR(0.2, 0.7), SpreadAngle = Vector2.new(40, 40), Acceleration = V(0, 1.5, 0), LightEmission = 0.6 }))
		table.insert(S.owned, emitter(x.blade, { Texture = VT.smoke4x4, flip = true, Color = ColorSequence.new(P.c1, P.dark), Size = seq(0, 0.4, 1, 1.2), Transparency = seq(0, 0.7, 1, 1), Lifetime = NR(0.8, 1.1), Rate = 3, Speed = NR(0.1, 0.4), Acceleration = V(0, -0.5, 0), LightEmission = 0.3 }))
	end,
	cut = function(S, x, P, tip) if x.t - (S.lastCutFx or 0) > 0.06 then S.lastCutFx = x.t; burst({ cf = CFrame.new(tip), tex = VT.bubble, color = ColorSequence.new(P.hot), size = NS(0.25, 0.4), life = NR(0.4, 0.7), speed = NR(1, 3), accel = V(0, 3, 0), n = 2, le = 0.6 }) end end,
	impacts = {
		function(hit, P, x) -- Venom Splash
			impactFrame(hit, P.c1, P.c2, 3.5, P, x)
			groundMark(hit, VT.splat, P.c1, 5 + P.p, 2, 0.1, 1.6)
			burst({ cf = hit * CFrame.new(0, 0.5, 0), tex = VT.ember, color = ColorSequence.new(P.hot, P.c1), size = NS(0.35, 0.2), life = NR(0.5, 0.9), speed = NR(9, 16), spread = Vector2.new(65, 65), accel = V(0, -45, 0), n = 20, le = 0.5 })
			burst({ cf = hit * CFrame.new(0, 0.3, 0), tex = VT.bubble, color = ColorSequence.new(P.hot), size = seq(0, 0.2, 1, 0.7), life = NR(0.8, 1.4), speed = NR(1, 3), spread = Vector2.new(50, 50), accel = V(0, 2.5, 0), n = 14, le = 0.6, hold = 2 })
		end,
		function(hit, P, x) -- Miasma: a cloud of poison rolls out
			impactFrame(hit, P.c1, P.c2, 3, P, x)
			for i = 1, 6 do burst({ cf = jitter(hit * CFrame.new(0, 0.8, 0), 1, 0), tex = VT.smoke4x4, flip = true, color = ColorSequence.new(P.c1, P.dark), size = seq(0, 2, 1, 5 + P.p), trans = seq(0, 0.35, 1, 1), life = NR(1.2, 1.7), speed = NR(3, 6), spread = Vector2.new(80, 15), drag = 1.4, n = 1, le = 0.3, hold = 2.2 }) end
			groundMark(hit, VT.splat, P.dark, 4, 1.6, 0.3, 1.2)
		end,
		function(hit, P, x) -- Boil: the ground bubbles and pops
			impactFrame(hit, P.c1, P.c2, 3, P, x)
			groundMark(hit, VT.splat, P.c1, 6 + P.p, 1.6, 0.15, 1.6)
			for i = 1, 10 + 2 * P.p do
				task.delay(rnd(0, 0.6), function()
					local at = jitter(hit * CFrame.new(0, 0.3, 0), 2.5, 0)
					local b = burst({ cf = at, tex = VT.bubble, color = ColorSequence.new(P.hot), size = seq(0, 0.2, 0.85, rnd(0.8, 1.4), 1, rnd(1.4, 1.8)), trans = seq(0, 0.1, 0.85, 0.2, 1, 1), life = NR(0.35, 0.5), n = 1, le = 0.6 })
					task.delay(0.4, function() burst({ cf = at, tex = VT.ember, color = ColorSequence.new(P.c1), size = NS(0.18, 0.1), life = NR(0.3, 0.5), speed = NR(4, 7), accel = V(0, -30, 0), n = 5, le = 0.4 }) end)
				end)
			end
		end,
	},
}

-- CRYSTAL
T.crystal = {
	slash = "double",
	presence = function(S, x, P)
		table.insert(S.owned, emitter(x.blade, { Texture = VT.spark, Color = ColorSequence.new(WHITE, P.c1), Size = seq(0, 0, 0.25, 0.3, 1, 0), Lifetime = NR(0.4, 0.7), Rate = 4 + 2 * P.p, Speed = NR(0, 0), LightEmission = 1, RotSpeed = NR(0, 0) }))
		table.insert(S.owned, emitter(x.blade, { Texture = VT.shard, Color = ColorSequence.new(P.hot, P.c1), Size = NS(0.3, 0.2), Lifetime = NR(0.8, 1.3), Rate = 1 + P.p * 0.6, Speed = NR(0.4, 1), SpreadAngle = Vector2.new(180, 180), Acceleration = V(0, -3, 0), RotSpeed = NR(-120, 120), LightEmission = 0.5 }))
	end,
	cut = T.ice.cut,
	impacts = {
		function(hit, P, x) -- Crystal Cluster: a bouquet of crystals erupts
			impactFrame(hit, P.c1, P.c2, 4, P, x)
			for i = 1, 6 + P.p do task.delay(i * 0.02, function() iceSpike(jitter(hit, 1.2, 0), P, rnd(1.4, 2.6) + 0.3 * P.p) end) end
			burst({ cf = hit * CFrame.new(0, 1, 0), tex = VT.spark, color = ColorSequence.new(WHITE, P.c1), size = NS(0.7, 0), life = NR(0.3, 0.6), speed = NR(6, 12), n = 14, le = 1, rot = NR(0, 0) })
		end,
		function(hit, P, x) -- Prism Shatter: glass blasts apart
			impactFrame(hit, P.c1, P.c2, 5, P, x)
			debris(hit, 8 + P.p, P.p + 1, P.hot:Lerp(P.c1, 0.5), Enum.Material.Glass)
			burst({ cf = hit * CFrame.new(0, 0.8, 0), tex = VT.shard, orient = Enum.ParticleOrientation.VelocityParallel, color = ColorSequence.new(P.hot, P.c1), size = NS(0.9, 0.2), life = NR(0.35, 0.6), speed = NR(16, 26), n = 16, le = 0.6, drag = 2, accel = V(0, -30, 0) })
			groundMark(hit, VT.frost, P.c1, 5 + P.p, 1.2, 0.2, 1.6)
		end,
		function(hit, P, x) -- Crystal Line: crystals march forward
			T.ice.impacts[2](hit, P, x)
		end,
	},
}

-- COSMIC
T.cosmic = {
	slash = "thin",
	presence = function(S, x, P)
		table.insert(S.owned, emitter(x.blade, { Texture = VT.spark, Color = ColorSequence.new(WHITE, P.c2), Size = seq(0, 0, 0.2, 0.25, 1, 0), Lifetime = NR(0.6, 1.1), Rate = 5 + 2 * P.p, Speed = NR(0.1, 0.4), LightEmission = 1, RotSpeed = NR(0, 0) }))
		table.insert(S.owned, emitter(x.blade, { Texture = VT.smoke4x4, flip = true, Color = ColorSequence.new(P.c1, P.dark), Size = seq(0, 0.6, 1, 1.4), Transparency = seq(0, 0.7, 1, 1), Lifetime = NR(1, 1.4), Rate = 2.5, Speed = NR(0.1, 0.3), LightEmission = 0.8 }))
	end,
	cut = T.arcane.cut,
	impacts = {
		function(hit, P, x) -- Starfall: a star streaks down and bursts
			T.fire.impacts[4](hit, P, x)
			task.delay(0.34, function() burst({ cf = hit * CFrame.new(0, 1, 0), tex = VT.spark, color = ColorSequence.new(WHITE, P.c2), size = NS(1.2, 0), life = NR(0.5, 0.9), speed = NR(8, 16), n = 18, le = 1, rot = NR(0, 0) }) end)
		end,
		function(hit, P, x) -- Nebula: a cloud of stars blooms
			impactFrame(hit, P.c1, P.c2, 4, P, x)
			for i = 1, 4 do burst({ cf = jitter(hit * CFrame.new(0, 1.2, 0), 1, 0), tex = VT.smoke4x4, flip = true, color = ColorSequence.new(P.c1, P.c2), size = seq(0, 2, 1, 5 + P.p), trans = seq(0, 0.3, 1, 1), life = NR(1, 1.4), speed = NR(2, 4), n = 1, le = 0.8, hold = 2 }) end
			burst({ cf = hit * CFrame.new(0, 1.2, 0), tex = VT.spark, color = ColorSequence.new(WHITE, P.c2), size = seq(0, 0, 0.2, 0.6, 1, 0), life = NR(0.8, 1.4), speed = NR(3, 7), drag = 1.5, n = 26, le = 1, rot = NR(0, 0) })
		end,
		function(hit, P, x) -- Constellation: points of light linked by beams
			impactFrame(hit, P.c1, P.c2, 3.5, P, x)
			local pts = {}
			for i = 1, 5 + P.p do pts[i] = (jitter(hit, 4, 0) * CFrame.new(0, rnd(0.6, 2.4), 0)).Position end
			for i, pt in ipairs(pts) do
				task.delay(i * 0.05, function()
					burst({ cf = CFrame.new(pt), tex = VT.spark, color = ColorSequence.new(WHITE, P.c2), size = NS(1.4, 0), life = NR(0.7, 0.9), n = 1, le = 1, rot = NR(0, 0) })
					if pts[i + 1] then beam(pt, pts[i + 1], VT.energyTrail, P.c2, 0.25, 0.8, { hold = 0.4 }) end
				end)
			end
		end,
		function(hit, P, x) T.arcane.impacts[1](hit, P, x) end,
	},
}

-- ECLIPSE
T.eclipse = {
	slash = "crescent",
	presence = T.void.presence,
	cut = T.void.cut,
	impacts = {
		function(hit, P, x) -- Totality: a black disc with a blazing corona
			impactFrame(hit, P.c2, P.c2, 4, P, x)
			local s = 3 + 0.4 * P.p
			local orb = part({ shape = Enum.PartType.Ball, size = V(s, s, s), cf = hit * CFrame.new(0, 2, 0), color = BLACK, mat = Enum.Material.SmoothPlastic, life = 0.9 })
			burst({ cf = hit * CFrame.new(0, 2, 0), tex = VT.lightRays, color = ColorSequence.new(P.c2), size = NS(s * 2.6, s * 3), life = NR(0.7, 0.7), n = 1, le = 1, z = -1, hold = 1, rot = NR(15, 25) })
			burst({ cf = hit * CFrame.new(0, 2, 0), tex = VT.bubble, color = ColorSequence.new(P.c2), size = NS(s * 1.15), life = NR(0.7, 0.7), n = 1, le = 1, hold = 1, rot = NR(0, 0) })
			task.delay(0.6, function() tw(orb, 0.2, { Size = V(0.1, 0.1, 0.1), Transparency = 1 }) end)
			local r, im = card(hit * CFrame.new(0, 0.1, 0), 2, VT.shockRing, P.c2, 0, 0.8, 3)
			tw(r, 0.35, { Size = V(11 + P.p, 0.05, 11 + P.p) }, Enum.EasingStyle.Quart); fadeImgs(im, 0.25, 0.1)
		end,
		function(hit, P, x) T.void.impacts[1](hit, P, x) end,
		function(hit, P, x) T.void.impacts[4](hit, P, x); burst({ cf = hit * CFrame.new(0, 1.2, 0), tex = VT.lightRays, color = ColorSequence.new(P.c2), size = NS(7, 9), life = NR(0.35, 0.45), n = 1, le = 0.9 }) end,
		function(hit, P, x) T.void.impacts[2](hit, P, x) end,
	},
}

-- PRISMATIC: every hit throws a spectrum
local SPECTRUM = cseq(0, Color3.fromHSV(0, 0.7, 1), 0.2, Color3.fromHSV(0.12, 0.7, 1), 0.4, Color3.fromHSV(0.3, 0.7, 1), 0.6, Color3.fromHSV(0.52, 0.7, 1), 0.8, Color3.fromHSV(0.7, 0.7, 1), 1, Color3.fromHSV(0.85, 0.7, 1))
T.prismatic = {
	slash = "thin",
	presence = function(S, x, P)
		table.insert(S.owned, emitter(x.blade, { Texture = VT.spark, Color = SPECTRUM, Size = seq(0, 0, 0.25, 0.3, 1, 0), Lifetime = NR(0.5, 0.9), Rate = 5 + 2 * P.p, Speed = NR(0.2, 0.6), SpreadAngle = Vector2.new(180, 180), LightEmission = 1, RotSpeed = NR(0, 0) }))
	end,
	cut = function(S, x, P, tip) if x.t - (S.lastCutFx or 0) > 0.04 then S.lastCutFx = x.t; burst({ cf = CFrame.new(tip), tex = VT.spark, color = ColorSequence.new(Color3.fromHSV((x.t * 1.7) % 1, 0.6, 1)), size = NS(0.8, 0), life = NR(0.3, 0.45), n = 1, le = 1, rot = NR(0, 0) }) end end,
	impacts = {
		function(hit, P, x) -- Spectrum Burst
			impactFrame(hit, P.c1, P.c2, 5, P, x)
			for i = 0, 4 do
				task.delay(i * 0.04, function()
					local r, im = card(hit * CFrame.new(0, 0.08 + i * 0.01, 0), 1.5, VT.ripple, Color3.fromHSV(i / 5, 0.7, 1), 0, 0.8, 3)
					tw(r, 0.45, { Size = V(8 + i * 1.6 + P.p, 0.05, 8 + i * 1.6 + P.p) }, Enum.EasingStyle.Quart); fadeImgs(im, 0.25, 0.2)
				end)
			end
			burst({ cf = hit * CFrame.new(0, 0.8, 0), tex = VT.sparkStreak, orient = Enum.ParticleOrientation.VelocityParallel, color = SPECTRUM, size = NS(0.7, 0), life = NR(0.3, 0.55), speed = NR(16, 26), drag = 2, n = 24, le = 1 })
		end,
		function(hit, P, x) T.crystal.impacts[2](hit, P, x); flareStreak(hit.Position + V(0, 1.3, 0), WHITE, 10, 0.25) end,
		function(hit, P, x) -- Refraction: light splits into coloured beams
			impactFrame(hit, P.c1, P.c2, 4, P, x)
			for i = 0, 5 do
				local a = i / 6 * TAU + rnd(-0.2, 0.2)
				beam(hit.Position + V(0, 1.2, 0), hit.Position + V(math.cos(a) * 7, rnd(0.5, 3), math.sin(a) * 7), VT.energyTrail, Color3.fromHSV(i / 6, 0.7, 1), 0.5, 0.45, { hold = 0.15, width1 = 0.1 })
			end
		end,
		function(hit, P, x) T.arcane.impacts[1](hit, P, x) end,
	},
}

-- TIDE (water)
T.tide = {
	slash = "swirl",
	presence = function(S, x, P)
		table.insert(S.owned, emitter(x.blade, { Texture = VT.ember, Color = ColorSequence.new(P.hot, P.c1), Size = NS(0.14, 0.1), Lifetime = NR(0.5, 0.8), Rate = 3 + P.p, Speed = NR(0, 0.3), Acceleration = V(0, -12, 0), LightEmission = 0.5 }))
		table.insert(S.owned, emitter(x.blade, { Texture = VT.smoke4x4, flip = true, Color = ColorSequence.new(P.hot, P.c1), Size = seq(0, 0.4, 1, 1.1), Transparency = seq(0, 0.8, 1, 1), Lifetime = NR(0.8, 1.1), Rate = 2.5, Speed = NR(0.1, 0.3), LightEmission = 0.3 }))
	end,
	cut = function(S, x, P, tip) if x.t - (S.lastCutFx or 0) > 0.05 then S.lastCutFx = x.t; burst({ cf = CFrame.new(tip), tex = VT.ember, color = ColorSequence.new(P.hot, P.c1), size = NS(0.2, 0.12), life = NR(0.4, 0.6), speed = NR(2, 6), accel = V(0, -35, 0), n = 4, le = 0.5 }) end end,
	impacts = {
		function(hit, P, x) -- Splash
			impactFrame(hit, P.c1, P.c2, 3.5, P, x)
			burst({ cf = hit * CFrame.new(0, 2, 0), tex = VT.splash4x4, flip = true, color = ColorSequence.new(P.hot, P.c1), size = NS(5 + P.p, 6 + P.p), life = NR(0.55, 0.6), n = 1, le = 0.5, rot = NR(0, 0), rotation = NR(-5, 5) })
			for i = 0, 2 do
				task.delay(i * 0.1, function()
					local r, im = card(hit * CFrame.new(0, 0.1, 0), 1.5, VT.ripple, P.hot, 0, 1, 2.2)
					tw(r, 0.6, { Size = V(8 + i * 2.5 + P.p, 0.05, 8 + i * 2.5 + P.p) }, Enum.EasingStyle.Quart); fadeImgs(im, 0.35, 0.25)
				end)
			end
			burst({ cf = hit * CFrame.new(0, 0.5, 0), tex = VT.ember, color = ColorSequence.new(P.hot, P.c1), size = NS(0.3, 0.15), life = NR(0.5, 0.9), speed = NR(10, 18), spread = Vector2.new(60, 60), accel = V(0, -50, 0), n = 22, le = 0.5 })
		end,
		function(hit, P, x) -- Whirlpool
			impactFrame(hit, P.c1, P.c2, 3, P, x)
			local s, im = card(hit * CFrame.new(0, 0.1, 0), 8 + P.p, VT.swirl, P.c1, 0.1, 1.3, 2)
			tw(s, 1, { CFrame = hit * CFrame.new(0, 0.1, 0) * CFrame.Angles(0, -6, 0), Size = V(3, 0.05, 3) }, Enum.EasingStyle.Quart, Enum.EasingDirection.In); fadeImgs(im, 0.4, 0.6)
			burst({ cf = hit * CFrame.new(0, 2, 0), tex = VT.splash4x4, flip = true, color = ColorSequence.new(P.hot, P.c1), size = NS(4, 5), life = NR(0.5, 0.55), n = 1, le = 0.5, rot = NR(0, 0) })
		end,
	},
}

---------------------------------------------------------------- factory
local function hex(s) return Color3.fromRGB(tonumber(s:sub(1, 2), 16) or 255, tonumber(s:sub(3, 4), 16) or 255, tonumber(s:sub(5, 6), 16) or 255) end
K.hex = hex
local function inCut(x) return x.swinging and x.st > 0.14 and x.st < 0.46 end

function K.palette(c1, c2, power, variant)
	c1, c2 = vivid(c1), vivid(c2)
	return { c1 = c1, c2 = c2, hot = c2:Lerp(WHITE, 0.6), dark = c1:Lerp(BLACK, 0.6), p = power, variant = variant }
end

function K.make(theme, variant, c1, c2, power)
	local kit = T[theme] or T.steel
	local P = K.palette(c1, c2, power, variant)
	local impacts = kit.impacts
	local impactFn = impacts[((variant or 1) - 1) % #impacts + 1]
	local steel = kit == T.steel
	local alpha = steel and (({ [0] = 0.45, 0.35, 0.18, 0.05 })[power] or 0.2) or 0
	local style = steel and (power >= 2 and "crescent" or "thin") or kit.slash or "crescent"
	local el = {
		trail = { Texture = VT.energyTrail, TextureMode = Enum.TextureMode.Stretch, LightInfluence = 0, LightEmission = steel and 0.85 or 1,
			Lifetime = steel and (0.18 + 0.04 * power) or (0.24 + 0.06 * power), WidthScale = NS(steel and (1 + 0.15 * power) or (1.2 + 0.2 * power), 0.2),
			Transparency = NS(steel and (0.1 + alpha * 0.5) or 0, 1), Color = cseq(0, WHITE, 0.35, P.hot, 1, P.c1) },
	}
	el.step = function(S, x)
		if not x.equipped or not x.char or not x.char.Parent then
			if S.folder then S.folder:Destroy(); S.folder = nil end
			if S.owned then for _, o in ipairs(S.owned) do o:Destroy() end; S.owned = nil end
			S.ready = false
			return
		end
		if not S.ready then
			S.ready = true
			S.folder = Instance.new("Folder"); S.folder.Name = "KitFX"; S.folder.Parent = x.tool
			S.owned = {}
			if not steel then
				table.insert(S.owned, emitter(x.blade, { Texture = VT.glow, Color = ColorSequence.new(P.c1), Size = NS(1.8 + 0.4 * power, 2.4 + 0.5 * power), Transparency = seq(0, 1, 0.45, 0.9 - 0.04 * power, 1, 1), Lifetime = NR(0.8, 1.1), Rate = 1.5 + power, Speed = NR(0, 0), LightEmission = 1 }))
				local l = Instance.new("PointLight"); l.Color = P.c1; l.Range = 5 + 2 * power; l.Brightness = 0.5 + 0.35 * power; l.Shadows = false; l.Parent = x.blade; table.insert(S.owned, l)
			end
			if kit.presence then pcall(kit.presence, S, x, P) end
			-- Mythic and Godly weapons carry a slowly turning seal at your feet
			if power >= 3 and not steel then S.seal = card(CFrame.new(), 5 + 0.5 * (power - 3), VT.runeRing, P.c1, 0.55, nil, 1.6, S.folder) end
			S.lastTip = nil
		end
		if kit.tick then kit.tick(S, x, P) end
		local tip = (x.blade.CFrame * CFrame.new(0, x.blade.Size.Y / 2, 0)).Position
		if S.seal then
			local hrp = x.char:FindFirstChild("HumanoidRootPart")
			if hrp and (not S.nextGround or x.t > S.nextGround) then
				S.nextGround = x.t + 0.15
				local _, _, gy = groundInfo(hrp.CFrame * CFrame.new(0, -2.5, 0))
				S.gy = gy
			end
			if hrp and S.gy then S.seal.CFrame = CFrame.new(hrp.Position.X, S.gy + 0.06, hrp.Position.Z) * CFrame.Angles(0, x.t * 0.35, 0) end
		end
		if not x.swinging then S.slashed = false end
		if inCut(x) and S.lastTip then
			local vel = tip - S.lastTip
			if not S.slashed and vel.Magnitude > 0.15 then
				S.slashed = true
				local hrp = x.char:FindFirstChild("HumanoidRootPart")
				if hrp then swingSlash(hrp.Position + V(0, 0.8, 0), tip, vel, P.c1, P.c2, style, steel and 0.9 or (0.95 + 0.06 * power), alpha) end
			end
			if kit.cut then kit.cut(S, x, P, tip) end
		end
		S.lastTip = tip
	end
	el.impact = function(x)
		local hit = x.ground * CFrame.new(0, 0, -3)
		impactFn(hit, P, x)
	end
	el.theme, el.palette = theme, P
	return el
end

K.themes = T
return K
