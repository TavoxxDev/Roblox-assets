local CHUVA_ATIVA = true

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Lighting = game:GetService("Lighting")
local Debris = game:GetService("Debris")

local config = {
	dropCount = 300,
	dropSpeed = 90,
	dropLength = 3.5,
	dropThickness = 0.04,
	spawnRadius = 120,
	spawnHeight = 60,
	windX = 8,
	windZ = 2,
	rainColor = Color3.fromRGB(180, 210, 240),
	rainTransparency = 0.45,
	puddleMax = 18,
	puddleLifetime = 12,
	splashCount = 5,
	transitionTime = 4,
}

local DROP_TILT = CFrame.Angles(math.rad(5), 0, 0)
local RAYCAST_DIR = Vector3.new(0, -200, 0)
local SPLASH_MAXFORCE = Vector3.new(1e5, 1e5, 1e5)
local TAU = math.pi * 2
local mrand = math.random
local mcos = math.cos
local msin = math.sin
local mabs = math.abs

local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude

local state = {
	drops = {},
	puddles = {},
	puddleCount = 0,
	conn = nil,
	folder = nil,
	atmosphere = nil,
	running = false,
	centerX = 0,
	centerY = 0,
	centerZ = 0,
}

local function updateCenter()
	local sx, sy, sz, n = 0, 0, 0, 0
	for _, player in ipairs(Players:GetPlayers()) do
		local char = player.Character
		if char then
			local root = char:FindFirstChild("HumanoidRootPart")
			if root then
				local p = root.Position
				sx += p.X
				sy += p.Y
				sz += p.Z
				n += 1
			end
		end
	end
	if n > 0 then
		state.centerX = sx / n
		state.centerY = sy / n
		state.centerZ = sz / n
	end
end

local function findGroundY(x, y, z)
	local result = workspace:Raycast(Vector3.new(x, y, z), RAYCAST_DIR, rayParams)
	return result and result.Position.Y or 0
end

local function spawnSplash(x, y, z)
	for i = 1, config.splashCount do
		local splash = Instance.new("Part")
		splash.Size = Vector3.new(0.08, 0.08, 0.08)
		splash.Shape = Enum.PartType.Ball
		splash.Material = Enum.Material.Neon
		splash.Color = config.rainColor
		splash.Transparency = 0.3
		splash.CastShadow = false
		splash.Anchored = false
		splash.CanCollide = false
		splash.Position = Vector3.new(x, y + 0.1, z)

		local angle = mrand() * TAU
		local speed = mrand(2, 6)
		local bv = Instance.new("BodyVelocity")
		bv.Velocity = Vector3.new(mcos(angle) * speed, mrand(3, 7), msin(angle) * speed)
		bv.MaxForce = SPLASH_MAXFORCE
		bv.Parent = splash
		splash.Parent = state.folder

		Debris:AddItem(splash, 0.35)
	end
end

local function removePuddle(idx)
	local last = state.puddleCount
	state.puddles[idx] = state.puddles[last]
	state.puddles[last] = nil
	state.puddleCount = last - 1
end

local function spawnPuddle(x, y, z)
	if state.puddleCount >= config.puddleMax then
		local oldest = state.puddles[1]
		if oldest and oldest.Parent then oldest:Destroy() end
		removePuddle(1)
	end

	local puddle = Instance.new("Part")
	puddle.Size = Vector3.new(0.1, 0.04, 0.1)
	puddle.Shape = Enum.PartType.Cylinder
	puddle.Material = Enum.Material.SmoothPlastic
	puddle.Color = Color3.fromRGB(140, 180, 210)
	puddle.Transparency = 0.5
	puddle.Anchored = true
	puddle.CanCollide = false
	puddle.CastShadow = false
	puddle.Position = Vector3.new(x, y + 0.02, z)
	puddle.Rotation = Vector3.new(0, 0, 90)
	puddle.Parent = state.folder

	state.puddleCount += 1
	state.puddles[state.puddleCount] = puddle

	local targetSize = Vector3.new(mrand(12, 28) / 10, 0.04, mrand(12, 28) / 10)
	TweenService:Create(puddle, TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Size = targetSize,
	}):Play()

	local capturedPuddle = puddle
	task.delay(config.puddleLifetime, function()
		if not capturedPuddle or not capturedPuddle.Parent then return end
		local fade = TweenService:Create(capturedPuddle, TweenInfo.new(1.5, Enum.EasingStyle.Quad), {
			Transparency = 1,
		})
		fade:Play()
		fade.Completed:Connect(function()
			if capturedPuddle.Parent then capturedPuddle:Destroy() end
			for i = 1, state.puddleCount do
				if state.puddles[i] == capturedPuddle then
					removePuddle(i)
					break
				end
			end
		end)
	end)
end

local function resetDrop(d, cx, cy, cz)
	local ox = (mrand() - 0.5) * 2 * config.spawnRadius
	local oz = (mrand() - 0.5) * 2 * config.spawnRadius
	d.x = cx + ox
	d.y = cy + config.spawnHeight + mrand() * 10
	d.z = cz + oz
	d.part.CFrame = CFrame.new(d.x, d.y, d.z) * DROP_TILT
end

local function createDrop(cx, cy, cz)
	local drop = Instance.new("Part")
	drop.Size = Vector3.new(config.dropThickness, config.dropLength, config.dropThickness)
	drop.Material = Enum.Material.Neon
	drop.Color = config.rainColor
	drop.Transparency = config.rainTransparency
	drop.Anchored = true
	drop.CanCollide = false
	drop.CastShadow = false
	drop.Parent = state.folder

	local ox = (mrand() - 0.5) * 2 * config.spawnRadius
	local oz = (mrand() - 0.5) * 2 * config.spawnRadius
	local x = cx + ox
	local y = cy + config.spawnHeight - mrand() * config.spawnHeight * 2
	local z = cz + oz

	drop.CFrame = CFrame.new(x, y, z) * DROP_TILT

	return { part = drop, x = x, y = y, z = z }
end

local function applyWeatherFX(enable)
	if not state.atmosphere then
		state.atmosphere = Lighting:FindFirstChildOfClass("Atmosphere") or Instance.new("Atmosphere", Lighting)
	end

	TweenService:Create(state.atmosphere, TweenInfo.new(config.transitionTime, Enum.EasingStyle.Quad), {
		Density = enable and 0.55 or 0.3,
		Color = enable and Color3.fromRGB(140, 160, 180) or Color3.fromRGB(255, 255, 255),
		Offset = 0,
	}):Play()

	TweenService:Create(Lighting, TweenInfo.new(config.transitionTime, Enum.EasingStyle.Quad), {
		Brightness = enable and 0.15 or 2.2,
	}):Play()
end

local function startRain()
	if state.running then return end
	state.running = true

	state.folder = Instance.new("Folder")
	state.folder.Name = "RainDrops"
	state.folder.Parent = workspace

	rayParams.FilterDescendantsInstances = { state.folder }

	updateCenter()
	local cx, cy, cz = state.centerX, state.centerY, state.centerZ

	for i = 1, config.dropCount do
		state.drops[i] = createDrop(cx, cy, cz)
	end

	applyWeatherFX(true)

	local frameSkip = 0
	local windX = config.windX
	local windZ = config.windZ
	local dropSpeed = config.dropSpeed
	local spawnRadius = config.spawnRadius
	local halfLen = config.dropLength / 2

	state.conn = RunService.Heartbeat:Connect(function(dt)
		frameSkip += 1
		if frameSkip >= 6 then
			frameSkip = 0
			updateCenter()
		end

		cx = state.centerX
		cy = state.centerY
		cz = state.centerZ

		local wx = windX * dt
		local wy = dropSpeed * dt
		local wz = windZ * dt
		local drops = state.drops

		for i = 1, #drops do
			local d = drops[i]
			local p = d.part
			if not p or not p.Parent then continue end

			d.x += wx
			d.y -= wy
			d.z += wz

			p.CFrame = CFrame.new(d.x, d.y, d.z) * DROP_TILT

			local groundY = findGroundY(d.x, d.y, d.z)

			if d.y <= groundY + halfLen then
				spawnSplash(d.x, groundY, d.z)
				if mrand() < 0.08 then spawnPuddle(d.x, groundY, d.z) end
				resetDrop(d, cx, cy, cz)
			elseif mabs(d.x - cx) > spawnRadius or mabs(d.z - cz) > spawnRadius then
				resetDrop(d, cx, cy, cz)
			end
		end
	end)
end

local function stopRain()
	if not state.running then return end
	state.running = false

	if state.conn then
		state.conn:Disconnect()
		state.conn = nil
	end

	for i = 1, #state.drops do
		local d = state.drops[i]
		if d.part and d.part.Parent then d.part:Destroy() end
	end
	state.drops = {}

	for i = 1, state.puddleCount do
		local p = state.puddles[i]
		if p and p.Parent then p:Destroy() end
	end
	state.puddles = {}
	state.puddleCount = 0

	if state.folder then
		state.folder:Destroy()
		state.folder = nil
	end

	applyWeatherFX(false)
end

if CHUVA_ATIVA then
	startRain()
end
