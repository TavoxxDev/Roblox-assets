local Players = game:GetService("Players")
local MarketplaceService = game:GetService("MarketplaceService")
local DataStoreService = game:GetService("DataStoreService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local pasta = script.Parent
local part = pasta.Placar
local tela = part.Tela
local framePrincipal = tela["1"]
local users = framePrincipal.Usuarios
local usersFolder = pasta.Users

local placares = {
	users["#1"], users["#2"], users["#3"],
	users["#4"], users["#5"], users["#6"],
	users["#7"], users["#8"], users["#9"],
}

local pedestais = {
	usersFolder["1"],
	usersFolder["2"],
	usersFolder["3"],
}

local doarTemplate = pasta.Doar.Gui["1"].Lista.Template
local donationStore = DataStoreService:GetDataStore("DoacoesStore_v1")
local estatuasAtuais = {}

local remoteProducts = Instance.new("RemoteEvent")
remoteProducts.Name = "GetProducts"
remoteProducts.Parent = ReplicatedStorage

local remoteComprar = Instance.new("RemoteEvent")
remoteComprar.Name = "ComprarProduct"
remoteComprar.Parent = ReplicatedStorage

local dancas = {
	507771019,
	507776043,
	507777268,
}

local function getAllProducts()
	local products = {}
	local success, pages = pcall(function()
		return MarketplaceService:GetDeveloperProductsAsync()
	end)
	if not success then return products end
	while true do
		local page = pages:GetCurrentPage()
		for _, product in ipairs(page) do
			table.insert(products, {
				id    = product.ProductId,
				preco = product.PriceInRobux or 0,
			})
		end
		if pages.IsFinished then break end
		pages:AdvanceToNextPageAsync()
	end
	table.sort(products, function(a, b)
		return a.preco < b.preco
	end)
	return products
end

local cachedProducts = {}

remoteProducts.OnServerEvent:Connect(function(player)
	remoteProducts:FireClient(player, cachedProducts)
end)

remoteComprar.OnServerEvent:Connect(function(player, productId)
	if type(productId) ~= "number" then return end
	MarketplaceService:PromptProductPurchase(player, productId)
end)

local function tocarDanca(modelo)
	local humanoid = modelo:FindFirstChildOfClass("Humanoid")
	if not humanoid then return end

	local animator = humanoid:FindFirstChildOfClass("Animator")
	if not animator then
		animator = Instance.new("Animator")
		animator.Parent = humanoid
	end

	local animId = dancas[math.random(1, #dancas)]
	local anim = Instance.new("Animation")
	anim.AnimationId = "rbxassetid://" .. animId

	local track = animator:LoadAnimation(anim)
	track.Looped = true
	track:Play()
end

local function criarModelo(pedestal, userId)
	local ok, desc = pcall(function()
		return Players:GetHumanoidDescriptionFromUserIdAsync(userId)
	end)
	if not ok then return nil end

	local ok2, modelo = pcall(function()
		return Players:CreateHumanoidModelFromDescriptionAsync(desc, Enum.HumanoidRigType.R15)
	end)
	if not ok2 then return nil end

	local humanoid = modelo:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
		humanoid.WalkSpeed = 0
		humanoid.JumpPower = 0
	end

	local rootPart = modelo:FindFirstChild("HumanoidRootPart")
	if rootPart then
		rootPart.Anchored = true
	end

	-- Parenta antes de animar
	modelo.Parent = workspace

	local pedestalCFrame = pedestal.CFrame
	local pedestalSize = pedestal.Size

	local spawnCFrame = CFrame.new(
		pedestalCFrame.Position + Vector3.new(0, pedestalSize.Y / 2 + 3, 0)
	) * CFrame.Angles(0, math.atan2(pedestalCFrame.LookVector.X, pedestalCFrame.LookVector.Z), 0)

	if rootPart then
		rootPart.CFrame = spawnCFrame
	else
		modelo:MoveTo(spawnCFrame.Position)
	end

	task.wait(0.1)
	tocarDanca(modelo)

	return modelo
end

local function spawnEstatua(index, pedestal, userId)
	local modelo = criarModelo(pedestal, userId)
	if not modelo then return end

	estatuasAtuais[index] = modelo

	local humanoid = modelo:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.Died:Connect(function()
			task.wait(10)
			if estatuasAtuais[index] == modelo then
				modelo:Destroy()
				estatuasAtuais[index] = nil
				spawnEstatua(index, pedestal, userId)
			end
		end)
	end

	task.spawn(function()
		while modelo and modelo.Parent do
			task.wait(10)
			if modelo and modelo.Parent then
				tocarDanca(modelo)
			end
		end
	end)
end

local function atualizarEstatuas(top)
	for i = 1, 3 do
		if estatuasAtuais[i] then
			estatuasAtuais[i]:Destroy()
			estatuasAtuais[i] = nil
		end
		if top[i] and pedestais[i] then
			spawnEstatua(i, pedestais[i], top[i].userId)
		end
	end
end

local function atualizarPlacar()
	local success, data = pcall(function()
		return donationStore:GetAsync("TopDoadoresGlobal")
	end)
	local top = (success and data) or {}
	table.sort(top, function(a, b)
		return (a.total or 0) > (b.total or 0)
	end)
	for i, placar in ipairs(placares) do
		local d = top[i]
		local nome  = placar:FindFirstChild("Nome")
		local robux = placar:FindFirstChild("Robux")
		local foto  = placar:FindFirstChild("User")
		if d then
			placar.Visible = true
			if nome  then nome.Text  = d.nome or "???" end
			if robux then robux.Text = "$ " .. (d.total or 0) end
			if foto  then
				foto.Image = "rbxthumb://type=AvatarHeadShot&id=" .. (d.userId or 0) .. "&w=420&h=420"
			end
		else
			placar.Visible = false
		end
	end
	atualizarEstatuas(top)
end

MarketplaceService.ProcessReceipt = function(receiptInfo)
	local player = Players:GetPlayerByUserId(receiptInfo.PlayerId)
	local robux  = receiptInfo.CurrencySpent
	local ok, err = pcall(function()
		local data = donationStore:GetAsync("TopDoadoresGlobal") or {}
		local encontrado = false
		for _, entry in ipairs(data) do
			if entry.userId == receiptInfo.PlayerId then
				entry.total = (entry.total or 0) + robux
				encontrado = true
				break
			end
		end
		if not encontrado then
			table.insert(data, {
				userId = receiptInfo.PlayerId,
				nome   = player and player.DisplayName or "Desconhecido",
				total  = robux,
			})
		end
		donationStore:SetAsync("TopDoadoresGlobal", data)
	end)
	if ok then
		atualizarPlacar()
		return Enum.ProductPurchaseDecision.PurchaseGranted
	else
		warn(tostring(err))
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
end

cachedProducts = getAllProducts()
atualizarPlacar()

while true do
	task.wait(10)
	atualizarPlacar()
end
