local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local Input = game:GetService("UserInputService")
local RunService = game:GetService("RunService")

-- Resolve capabilities by type: a truthy unsupported alias must not hide a working one.
local Environment = _G
if type(getgenv) == "function" then
	local ok, environment = pcall(getgenv)
	if ok and type(environment) == "table" then
		Environment = environment
	end
end
local function capability(...)
	for index = 1, select("#", ...) do
		local name = select(index, ...)
		local value = Environment[name]
		if type(value) == "function" then
			return value
		end
		value = getfenv()[name]
		if type(value) == "function" then
			return value
		end
		value = _G[name]
		if type(value) == "function" then
			return value
		end
	end
	return nil
end
local function nestedCapability(namespace, name)
	for _, root in ipairs({ Environment, getfenv(), _G }) do
		local api = root[namespace]
		if type(api) == "table" and type(api[name]) == "function" then
			return api[name]
		end
	end
	return nil
end
local IdentitySetter = capability("setthreadidentity", "set_thread_identity", "setidentity")
	or nestedCapability("syn", "set_thread_identity")
if type(IdentitySetter) == "function" then
	pcall(IdentitySetter, 6)
end

local logoUrl =
	"https://vampauth.com/api/avatar/file/avatars/19499984-8998-4f2a-8253-8e4d1b89e271/uxpzw9ebamf_1792664527021.webp"
local keyLink = "https://vampauth.com/sntl/flow"
local keyFolder = "Sentinel Studio"
local keyFile = keyFolder .. "/key.txt"
local MAX_KEY_BYTES = 1024
local MAX_SOURCE_BYTES = 8 * 1024 * 1024
local REQUEST_TIMEOUT = 12
local MAX_ATTEMPTS = 3

local function normalizeKey(value)
	if type(value) ~= "string" or #value > MAX_KEY_BYTES then
		return nil
	end
	value = value:gsub("^\239\187\191", ""):match("^%s*(.-)%s*$")
	if value == "" or value:find("[%z\1-\31\127]") then
		return nil
	end
	return value
end

local function readSavedKey()
	local reader = capability("readfile")
	local exists = capability("isfile")
	if not reader then
		return nil
	end
	local ok, saved = pcall(function()
		if exists and not exists(keyFile) then
			return nil
		end
		return reader(keyFile)
	end)
	if not ok or type(saved) ~= "string" then
		return nil
	end
	return normalizeKey(saved)
end

local function saveKey(key)
	local writer = capability("writefile")
	if not writer then
		return false
	end
	return pcall(function()
		local makeFolder = capability("makefolder")
		local isFolder = capability("isfolder")
		if makeFolder then
			local folderExists = false
			if isFolder then
				local ok, result = pcall(isFolder, keyFolder)
				folderExists = ok and result == true
			end
			if not folderExists then
				pcall(makeFolder, keyFolder)
			end
		end
		writer(keyFile, key)
	end)
end

local function fail(code)
	-- Never surface a provider response or a script error that could contain the key.
	error({ sentinelLoaderError = code }, 0)
end

local function stopTask(thread)
	if type(task.cancel) == "function" and coroutine.status(thread) ~= "dead" then
		pcall(task.cancel, thread)
	end
end

local function boundedCall(callback, isActive)
	local result
	local thread = task.spawn(function()
		result = table.pack(pcall(callback))
	end)
	local deadline = os.clock() + REQUEST_TIMEOUT
	while not result do
		if isActive and not isActive() then
			stopTask(thread)
			fail("cancelled")
		end
		if os.clock() >= deadline then
			stopTask(thread)
			return false, nil, "timeout", true
		end
		task.wait(0.05)
	end
	if isActive and not isActive() then
		fail("cancelled")
	end
	if not result[1] then
		return false, nil, "network", true
	end
	return true, table.unpack(result, 2, result.n)
end

local function validateBody(body)
	if type(body) ~= "string" or body:match("^%s*$") then
		return nil, "empty", true
	end
	if #body > MAX_SOURCE_BYTES then
		return nil, "tooLarge", false
	end
	return body
end

local function httpGet(url, isActive)
	local requester = capability("request", "http_request") or nestedCapability("syn", "request")
	local lastError = "network"
	for attempt = 1, MAX_ATTEMPTS do
		if isActive and not isActive() then
			fail("cancelled")
		end
		local ok, body, reason, retryable, retryAfter = boundedCall(function()
			if requester then
				local requestOk, response = pcall(requester, {
					Url = url,
					Method = "GET",
					Timeout = REQUEST_TIMEOUT,
				})
				if requestOk and type(response) == "table" then
					local status = tonumber(response.StatusCode or response.Status or response.status_code)
					if status and (status < 200 or status >= 300) then
						local headers = response.Headers or response.headers
						local delay = type(headers) == "table" and tonumber(headers["Retry-After"] or headers["retry-after"])
						return nil, "http" .. tostring(status), status == 408 or status == 425 or status == 429 or status >= 500, delay
					end
					if response.Success ~= false then
						return validateBody(response.Body or response.body)
					end
				end
			end
			-- Some executors only provide HttpGet, others expose a broken request alias.
			return validateBody(game:HttpGet(url))
		end, isActive)
		if ok and body then
			return body
		end
		lastError = reason or "network"
		if not retryable or attempt == MAX_ATTEMPTS then
			break
		end
		local delay = math.clamp(retryAfter or 2 ^ (attempt - 1), 0, 5)
		local deadline = os.clock() + delay
		repeat
			if isActive and not isActive() then
				fail("cancelled")
			end
			task.wait(0.05)
		until os.clock() >= deadline
	end
	return fail(lastError)
end

local GameCatalog = {
	[101770480176177] = "53b9be9121357bb73a0295e91d178357", -- Command An Army
	[113218456271570] = "53b9be9121357bb73a0295e91d178357", -- Command An Army (Zombie)
	[107778070777162] = "4836c1b2793b60c954f44b523235378a", -- Steal An Egg
	[72858262610964] = "529acecb435a82afaf92fe0e83fb04f2", -- Tap Simulator REBORN
	[126987974021910] = "d9a6312cd7f9df96799de71e604fc990", -- Illegal Soccer
	[107535308163741] = "b92ef76518127fd7f7ee5173cf3b0ca9", -- Huss Valley
	[113290951185459] = "6774f2ac818c872ba6cade68c0f72f15", -- Anime Dice
	[114326934417838] = "60afde9ea5ca19a22d57c9421f145958", -- Break and Steal an Egg
	[81440632616906] = "ae0e4359ac03cad856c83e5516c019a0", -- Dig to Earth's CORE!
	[140067658687251] = "777402ee029f29d5349f25eca2185acb", -- Rope an Animal
	[99409088950210] = "8f21934dbe603c29370d42602c94e3f0", -- Survive a Million Monkeys
	[76943966208523] = "e9331de35c476acd84aa69872be51519", -- Clone to Steal Eggs
	[99679692310083] = "5f20847938331adde420ee401d23440b", -- Steal Animal Egg
	[97927337336367] = "60bb8ad8c4b6a37440f0a4bd0b895316", -- SCROOMS
	[73956553001240] = "6c95c648da3b4cbc5a8a8c3833fef1ef", -- Volleyball Legends
	[93523763376122] = "926344409ff6fc1d5fa237e3a9392383", -- Ride a Dino (and Catch Them All)
	[142823291] = "f3ff01788ca2247c662a6a4fecaa2c56", -- Murder Mystery 2
	[116448925875915] = "116c40ef2e4529b5d5cf1281231bbe63", -- +1 Venom Evolution
	[79546208627805] = "36f18f2df77cb696670f7291e460592c", -- 99 Nights in the Forest
	[13379208636] = "7d7169f946b0b029b83e0c578b8eae14", -- Attack on Titan Revolution
	[130878180532794] = "23134d49c0c1cb5d61220a2c59b38276", -- RoChess
	[137629355240872] = "5d5bd3cb69e35584627a450143646231", -- GloryBound
	[137151641329864] = "f809fd3b84be204c958647d437f58916", -- ROFRONT / RoWorld (RAW, latest version)
	[85738654635245] = "b2301b971dc6f218e712eb9aafa0680b", -- Climb For Animals Eggs
	[103363457515322] = "c38412b4e6c1214666590ee587137fe6", -- Chop A Forest
	[116495829188952] = "639e85ed1cda04445dbdfc5c19e4db84", -- Dead Rails
	[16732694052] = "d1cd28f95070997b56f4d836f295715c", -- Fisch
	[101880234193261] = "62b231ab3aeefcfbfa0275dfcad0448e", -- Turbo Soccer
	[120219252362013] = "e63b360b3ef4432784be44dfc06c891f", -- Throw Food For Animals
}

-- Recognize the same games after teleporting between lobbies and mission places.
local UniverseCatalog = {
	[10258991999] = "53b9be9121357bb73a0295e91d178357", -- Command An Army
	[10563114921] = "4836c1b2793b60c954f44b523235378a", -- Steal An Egg
	[10629695169] = "529acecb435a82afaf92fe0e83fb04f2", -- Tap Simulator REBORN
	[10155360168] = "d9a6312cd7f9df96799de71e604fc990", -- Illegal Soccer
	[10764627709] = "b92ef76518127fd7f7ee5173cf3b0ca9", -- Huss Valley
	[10708913337] = "6774f2ac818c872ba6cade68c0f72f15", -- Anime Dice
	[10765288803] = "60afde9ea5ca19a22d57c9421f145958", -- Break and Steal an Egg
	[7468338447] = "ae0e4359ac03cad856c83e5516c019a0", -- Dig to Earth's CORE!
	[10764415267] = "777402ee029f29d5349f25eca2185acb", -- Rope an Animal
	[10673920146] = "8f21934dbe603c29370d42602c94e3f0", -- Survive a Million Monkeys
	[10766008884] = "e9331de35c476acd84aa69872be51519", -- Clone to Steal Eggs
	[10766056678] = "5f20847938331adde420ee401d23440b", -- Steal Animal Egg
	[10292064735] = "60bb8ad8c4b6a37440f0a4bd0b895316", -- SCROOMS
	[6931042565] = "6c95c648da3b4cbc5a8a8c3833fef1ef", -- Volleyball Legends
	[10758824872] = "926344409ff6fc1d5fa237e3a9392383", -- Ride a Dino (and Catch Them All)
	[66654135] = "f3ff01788ca2247c662a6a4fecaa2c56", -- Murder Mystery 2
	[10769464063] = "116c40ef2e4529b5d5cf1281231bbe63", -- +1 Venom Evolution
	[7326934954] = "36f18f2df77cb696670f7291e460592c", -- 99 Nights in the Forest
	[4658598196] = "7d7169f946b0b029b83e0c578b8eae14", -- Attack on Titan Revolution
	[10773907070] = "23134d49c0c1cb5d61220a2c59b38276", -- RoChess
	[10768652372] = "5d5bd3cb69e35584627a450143646231", -- GloryBound
	[10768172922] = "f809fd3b84be204c958647d437f58916", -- ROFRONT / RoWorld (RAW, latest version)
	[10765490774] = "b2301b971dc6f218e712eb9aafa0680b", -- Climb For Animals Eggs
	[10767386157] = "c38412b4e6c1214666590ee587137fe6", -- Chop A Forest
	[7018190066] = "639e85ed1cda04445dbdfc5c19e4db84", -- Dead Rails
	[5750914919] = "d1cd28f95070997b56f4d836f295715c", -- Fisch
	[10767012496] = "62b231ab3aeefcfbfa0275dfcad0448e", -- Turbo Soccer
	[10766972131] = "e63b360b3ef4432784be44dfc06c891f", -- Throw Food For Animals
}

local function createWindow()
	local parent = Players.LocalPlayer:WaitForChild("PlayerGui")
	pcall(function()
		parent = gethui()
	end)
	local old = parent:FindFirstChild("SentinelKeyUI")
	if old then
		old:Destroy()
	end

	local C = {
		panel = Color3.fromRGB(18, 19, 21),
		field = Color3.fromRGB(12, 13, 15),
		raised = Color3.fromRGB(27, 29, 32),
		line = Color3.fromRGB(43, 45, 50),
		white = Color3.fromRGB(235, 236, 238),
		muted = Color3.fromRGB(126, 130, 138),
		accent = Color3.fromRGB(91, 141, 239),
		ink = Color3.fromRGB(10, 17, 29),
	}
	local mobile = Input.TouchEnabled
	local panelWidth = mobile and 360 or 420
	local panelHeight = mobile and 270 or 292
	local collapsedHeight = mobile and 64 or 60
	local collapsedWidth = mobile and 300 or panelWidth
	local gutter = mobile and 16 or 20
	local headerHeight = mobile and 64 or 72
	local headerButtonSize = mobile and 40 or 28
	local function make(class, props, owner)
		local object = Instance.new(class)
		for key, value in pairs(props) do
			object[key] = value
		end
		object.Parent = owner
		return object
	end
	local function corner(object, radius)
		make("UICorner", { CornerRadius = UDim.new(0, radius) }, object)
	end
	local function border(object)
		return make(
			"UIStroke",
			{ Color = C.line, Thickness = 1, ApplyStrokeMode = Enum.ApplyStrokeMode.Border },
			object
		)
	end
	local function animate(object, props, duration)
		local tween = TweenService:Create(
			object,
			TweenInfo.new(duration or 0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			props
		)
		tween:Play()
		return tween
	end
	local function text(owner, value, size, position, dimensions, color, bold)
		return make("TextLabel", {
			Text = value,
			TextSize = size,
			Font = bold and Enum.Font.GothamBold or Enum.Font.Gotham,
			BackgroundTransparency = 1,
			TextColor3 = color or C.white,
			TextXAlignment = Enum.TextXAlignment.Left,
			Position = position,
			Size = dimensions,
		}, owner)
	end
	local connections, alive = {}, true
	local function on(signal, fn)
		local connection = signal:Connect(fn)
		table.insert(connections, connection)
	end
	local gui = make("ScreenGui", {
		Name = "SentinelKeyUI",
		ResetOnSpawn = false,
		DisplayOrder = 100,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		IgnoreGuiInset = false,
	}, parent)
	local root = make("Frame", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1 }, gui)
	local window = make("Frame", {
		Name = "Window",
		BackgroundColor3 = C.panel,
		BackgroundTransparency = 0.08,
		BorderSizePixel = 0,
		ClipsDescendants = true,
		Size = UDim2.fromOffset(panelWidth, panelHeight),
	}, root)
	corner(window, 8)
	border(window)
	local handle = make("TextButton", {
		Name = "DragHandle",
		Text = "",
		BackgroundTransparency = 1,
		Size = UDim2.new(1, mobile and -104 or -92, 0, headerHeight),
		AutoButtonColor = false,
		Active = true,
	}, window)
	local mark = make("Frame", {
		BackgroundColor3 = C.raised,
		BorderSizePixel = 0,
		Position = UDim2.fromOffset(gutter, mobile and 16 or 22),
		Size = UDim2.fromOffset(mobile and 32 or 28, mobile and 32 or 28),
	}, handle)
	corner(mark, 6)
	local markText = text(mark, "S", 15, UDim2.fromScale(0, 0), UDim2.fromScale(1, 1), C.ink, true)
	markText.TextXAlignment = Enum.TextXAlignment.Center
	markText.TextColor3 = C.accent
	local logo = make("ImageLabel", {
		Name = "Logo",
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(2, 2),
		Size = UDim2.new(1, -4, 1, -4),
		ScaleType = Enum.ScaleType.Crop,
		Image = "",
		Visible = false,
	}, mark)
	corner(logo, 4)
	task.spawn(function()
		local assetLoader = getcustomasset or getsynasset
		if type(assetLoader) ~= "function" or type(writefile) ~= "function" then
			return
		end
		local loaded, asset = pcall(function()
			local path = "sentinel-logo.webp"
			local hasFile = type(isfile) == "function" and isfile(path)
			if not hasFile then
				writefile(path, httpGet(logoUrl))
			end
			return assetLoader(path)
		end)
		if loaded and type(asset) == "string" and asset ~= "" and logo.Parent then
			logo.Image = asset
			logo.Visible = true
			markText.Visible = false
		end
	end)
	local titleX = mobile and 58 or 60
	text(
		handle,
		"SENTINEL",
		15,
		UDim2.fromOffset(titleX, mobile and 13 or 17),
		UDim2.fromOffset(150, 20),
		C.white,
		true
	)
	text(
		handle,
		"KEY ACCESS",
		10,
		UDim2.fromOffset(titleX, mobile and 34 or 38),
		UDim2.fromOffset(150, 16),
		C.muted,
		true
	)
	local minimize = make("TextButton", {
		Name = "Minimize",
		Text = "-",
		BackgroundTransparency = 1,
		Position = UDim2.new(1, mobile and -96 or -82, 0, mobile and 12 or 20),
		Size = UDim2.fromOffset(headerButtonSize, headerButtonSize),
		TextSize = 18,
		Font = Enum.Font.GothamMedium,
		TextColor3 = C.muted,
		BackgroundColor3 = C.line,
		BorderSizePixel = 0,
		AutoButtonColor = false,
	}, window)
	corner(minimize, 5)
	on(minimize.MouseEnter, function()
		animate(minimize, { BackgroundTransparency = 0 })
	end)
	on(minimize.MouseLeave, function()
		animate(minimize, { BackgroundTransparency = 1 })
	end)
	local close = make("TextButton", {
		Name = "Close",
		Text = "",
		BackgroundTransparency = 1,
		Position = UDim2.new(1, mobile and -48 or -46, 0, mobile and 12 or 20),
		Size = UDim2.fromOffset(headerButtonSize, headerButtonSize),
		BackgroundColor3 = C.line,
		BorderSizePixel = 0,
		AutoButtonColor = false,
	}, window)
	corner(close, 5)
	for _, angle in ipairs({ 45, -45 }) do
		make("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromOffset(11, 1),
			Rotation = angle,
			BackgroundColor3 = C.muted,
			BorderSizePixel = 0,
		}, close)
	end
	on(close.MouseEnter, function()
		animate(close, { BackgroundTransparency = 0 })
	end)
	on(close.MouseLeave, function()
		animate(close, { BackgroundTransparency = 1 })
	end)
	on(close.Activated, function()
		gui:Destroy()
	end)

	make("Frame", {
		Position = UDim2.fromOffset(gutter, headerHeight - 1),
		Size = UDim2.new(1, -gutter * 2, 0, 1),
		BackgroundColor3 = C.line,
		BorderSizePixel = 0,
	}, window)
	local description = text(
		window,
		"LICENSE KEY",
		10,
		UDim2.fromOffset(gutter, mobile and 78 or 91),
		UDim2.new(1, -gutter * 2, 0, 16),
		C.muted,
		true
	)
	local field = make("Frame", {
		Name = "KeyField",
		Position = UDim2.fromOffset(gutter, mobile and 98 or 114),
		Size = UDim2.new(1, -gutter * 2, 0, mobile and 48 or 50),
		BackgroundColor3 = C.field,
		BackgroundTransparency = 0.12,
		BorderSizePixel = 0,
	}, window)
	corner(field, 5)
	local outline = border(field)
	local input = make("TextBox", {
		Name = "KeyInput",
		Text = "",
		PlaceholderText = "Paste key",
		ClearTextOnFocus = false,
		MultiLine = false,
		TextSize = 15,
		Font = Enum.Font.Gotham,
		TextColor3 = C.white,
		PlaceholderColor3 = Color3.fromRGB(106, 109, 117),
		TextXAlignment = Enum.TextXAlignment.Left,
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(15, 0),
		Size = UDim2.new(1, -30, 1, 0),
	}, field)
	on(input.Focused, function()
		animate(outline, { Color = C.accent })
	end)
	on(input.FocusLost, function()
		animate(outline, { Color = C.line })
	end)

	local function button(value, primary, position, size)
		local base = primary and C.accent or C.raised
		local hover = primary and Color3.fromRGB(116, 160, 245) or Color3.fromRGB(35, 37, 41)
		local b = make("TextButton", {
			Text = value,
			Position = position,
			Size = size,
			Font = Enum.Font.GothamMedium,
			TextSize = 14,
			BorderSizePixel = 0,
			BackgroundColor3 = base,
			TextColor3 = primary and C.ink or C.white,
			AutoButtonColor = false,
		}, window)
		corner(b, 5)
		if not primary then
			border(b)
		end
		local hovering, pressed = false, false
		local function update()
			animate(
				b,
				{ BackgroundColor3 = pressed and (primary and C.white or C.line) or (hovering and hover or base) },
				0.14
			)
		end
		on(b.MouseEnter, function()
			hovering = true
			update()
		end)
		on(b.MouseLeave, function()
			hovering = false
			update()
		end)
		on(b.InputBegan, function(event)
			if
				event.UserInputType == Enum.UserInputType.Touch
				or event.UserInputType == Enum.UserInputType.MouseButton1
			then
				pressed = true
				update()
			end
		end)
		on(Input.InputEnded, function(event)
			if
				pressed
				and (
					event.UserInputType == Enum.UserInputType.Touch
					or event.UserInputType == Enum.UserInputType.MouseButton1
				)
			then
				pressed = false
				update()
			end
		end)
		return b
	end
	local enter =
		button("CONTINUE", true, UDim2.fromOffset(gutter, mobile and 158 or 180), UDim2.new(1, -gutter * 2, 0, 44))
	local getKey = button(
		"GET A KEY",
		false,
		UDim2.fromOffset(gutter, mobile and 214 or 234),
		UDim2.fromOffset(116, mobile and 40 or 34)
	)
	local feedback = text(
		window,
		"vampauth.com/sntl/flow",
		11,
		UDim2.fromOffset(mobile and 142 or 150, mobile and 225 or 242),
		UDim2.new(1, mobile and -158 or -170, 0, 18),
		C.muted
	)
	feedback.TextXAlignment = Enum.TextXAlignment.Right
	local function setStatus(message, highlighted)
		feedback.Text = message
		animate(feedback, { TextColor3 = highlighted and C.accent or C.muted })
	end

	local width, height, collapsed = panelWidth, panelHeight, false
	local sizeTween
	local content = { description, field, enter, getKey, feedback }
	local position = Vector2.new()
	local initialized, dragging = false, false
	local touch, pointerStart, windowStart
	local function visibleWidth()
		return collapsed and collapsedWidth or width
	end
	local function clampPosition(p)
		local viewport = root.AbsoluteSize
		return Vector2.new(
			math.floor(math.clamp(p.X, 0, math.max(0, viewport.X - visibleWidth())) + 0.5),
			math.floor(math.clamp(p.Y, 0, math.max(0, viewport.Y - (collapsed and collapsedHeight or height))) + 0.5)
		)
	end
	local function place(p)
		position = clampPosition(p)
		window.Position = UDim2.fromOffset(position.X, position.Y)
	end
	local function fit()
		local viewport = root.AbsoluteSize
		if viewport.X < 1 or viewport.Y < 1 then
			return
		end
		width = math.min(panelWidth, math.max(1, viewport.X - (mobile and 16 or 24)))
		collapsedWidth = mobile and math.min(300, width) or width
		if sizeTween then
			sizeTween:Cancel()
		end
		window.Size = UDim2.fromOffset(visibleWidth(), collapsed and collapsedHeight or height)
		if not initialized then
			initialized = true
			place(Vector2.new((viewport.X - visibleWidth()) / 2, (viewport.Y - height) / 2))
		else
			dragging = false
			place(position)
		end
	end
	on(root:GetPropertyChangedSignal("AbsoluteSize"), fit)
	fit()
	local function beginDrag(event)
		local isTouch = event.UserInputType == Enum.UserInputType.Touch
		if dragging or (not isTouch and event.UserInputType ~= Enum.UserInputType.MouseButton1) then
			return
		end
		dragging = true
		touch = isTouch and event or nil
		pointerStart = isTouch and Vector2.new(event.Position.X, event.Position.Y) or Input:GetMouseLocation()
		windowStart = position
	end
	on(handle.InputBegan, beginDrag)
	local edges = {}
	for _, spec in
		ipairs(mobile and {} or {
			{ "Bottom", UDim2.new(0, 0, 1, -16), UDim2.new(1, 0, 0, 16) },
			{ "Left", UDim2.fromOffset(0, 60), UDim2.new(0, 14, 1, -76) },
			{ "Right", UDim2.new(1, -14, 0, 60), UDim2.new(0, 14, 1, -76) },
		})
	do
		local edge = make("TextButton", {
			Name = spec[1] .. "Drag",
			Text = "",
			BackgroundTransparency = 1,
			Position = spec[2],
			Size = spec[3],
			Active = true,
			AutoButtonColor = false,
		}, window)
		table.insert(edges, edge)
		on(edge.InputBegan, beginDrag)
	end
	on(RunService.RenderStepped, function()
		if not dragging then
			return
		end
		local pointer = touch and Vector2.new(touch.Position.X, touch.Position.Y) or Input:GetMouseLocation()
		place(windowStart + (pointer - pointerStart))
	end)
	on(Input.InputEnded, function(event)
		if event == touch or (not touch and event.UserInputType == Enum.UserInputType.MouseButton1) then
			dragging = false
			touch = nil
		end
	end)
	on(Input.WindowFocusReleased, function()
		dragging = false
		touch = nil
	end)
	on(gui.Destroying, function()
		alive = false
		for _, connection in ipairs(connections) do
			connection:Disconnect()
		end
	end)

	local function revealText(owner)
		local objects = { owner }
		for _, child in ipairs(owner:GetDescendants()) do
			table.insert(objects, child)
		end
		for _, object in ipairs(objects) do
			if object:IsA("TextLabel") or object:IsA("TextButton") or object:IsA("TextBox") then
				object.TextTransparency = 1
				animate(object, { TextTransparency = 0 }, 0.32)
			end
		end
	end
	revealText(window)
	on(minimize.Activated, function()
		collapsed = not collapsed
		minimize.Text = collapsed and "+" or "-"
		for _, object in ipairs(content) do
			object.Visible = not collapsed
		end
		for _, edge in ipairs(edges) do
			edge.Visible = not collapsed
		end
		if collapsed then
			input:ReleaseFocus()
		end
		if sizeTween then
			sizeTween:Cancel()
		end
		local viewport = root.AbsoluteSize
		sizeTween = animate(window, {
			Size = UDim2.fromOffset(visibleWidth(), collapsed and collapsedHeight or height),
		}, 0.28)
		if mobile then
			position = Vector2.new((viewport.X - visibleWidth()) / 2, position.Y)
		end
		place(position)
		if not collapsed then
			for _, object in ipairs(content) do
				revealText(object)
			end
		end
	end)

	return {
		key = input,
		submit = enter,
		copy = getKey,
		connect = on,
		status = setStatus,
		exists = function()
			return alive
		end,
		loading = function(value)
			input.TextEditable = not value
			enter.Text = value and "LOADING..." or "CONTINUE"
		end,
	}
end

local function findLoader()
	return GameCatalog[game.PlaceId] or UniverseCatalog[game.GameId]
end

if not game:IsLoaded() then
	game.Loaded:Wait()
end
local playerDeadline = os.clock() + 15
while not Players.LocalPlayer and os.clock() < playerDeadline do
	task.wait(0.05)
end
if not Players.LocalPlayer then
	warn("[Sentinel Loader] Local player unavailable. Run the loader in a client session.")
	return
end

-- Keep the execution lock across loader re-executions, scoped to this server/place.
local runtimeKey = "__SentinelLoaderRuntime"
local session = tostring(game.PlaceId) .. ":" .. tostring(game.JobId)
local runtime = Environment[runtimeKey]
if type(runtime) ~= "table" or runtime.version ~= 1 or runtime.session ~= session then
	runtime = { version = 1, session = session, loaded = {} }
	Environment[runtimeKey] = runtime
end
if runtime.attempt and runtime.attempt.stage == "downloading" then
	runtime.attempt.cancelled = true
	runtime.attempt = nil
end

local ui = createWindow()
local savedKey = readSavedKey()
if savedKey then
	ui.key.Text = savedKey
end
local running, copying = false, false
local messageId = 0

local function notify(message, highlighted)
	messageId = messageId + 1
	if ui.exists() then
		ui.status(message, highlighted)
	end
	return messageId
end

local function copyToClipboard(value)
	local clipboard = capability("setclipboard", "toclipboard")
	if not clipboard then
		return false
	end
	local ok, result = pcall(clipboard, value)
	return ok and result ~= false
end

local function compileChunk(source)
	local compiler = capability("loadstring", "load")
	if not compiler then
		return nil, "compiler"
	end
	source = source:gsub("^\239\187\191", "")
	local prefix = source:sub(1, 256):lower():match("^%s*(.*)")
	if prefix:sub(1, 1) == "<" or prefix:sub(1, 1) == "{" or prefix:sub(1, 1) == "[" then
		return nil, "response"
	end
	local ok, chunk = pcall(compiler, source, "=SentinelGameLoader")
	if not ok or type(chunk) ~= "function" then
		return nil, "compile"
	end
	return chunk
end

-- The template carries itself to the next server, without reopening the key UI.
local TeleportTemplate = [=[
local function resume(key, loader, universe)
	if not game:IsLoaded() then game.Loaded:Wait() end
	if game.GameId ~= universe then return end
	local environment = _G
	if type(getgenv) == "function" then
		local ok, value = pcall(getgenv)
		if ok and type(value) == "table" then environment = value end
	end
	local function resolve(...)
		for index = 1, select("#", ...) do
			local name = select(index, ...)
			for _, root in ipairs({ environment, getfenv(), _G }) do
				if type(root[name]) == "function" then return root[name] end
			end
		end
		return nil
	end
	local function nested(namespace, name)
		for _, root in ipairs({ environment, getfenv(), _G }) do
			local api = root[namespace]
			if type(api) == "table" and type(api[name]) == "function" then return api[name] end
		end
		return nil
	end
	local identity = resolve("setthreadidentity", "set_thread_identity", "setidentity") or nested("syn", "set_thread_identity")
	if identity then pcall(identity, 6) end
	local compiler = resolve("loadstring", "load")
	if not compiler then warn("[Sentinel Loader] Lua compiler unavailable after teleport.") return end
	local session = tostring(game.PlaceId) .. ":" .. tostring(game.JobId)
	local runtime = environment.__SentinelLoaderRuntime
	if type(runtime) ~= "table" or runtime.version ~= 1 or runtime.session ~= session then
		runtime = { version = 1, session = session, loaded = {} }
		environment.__SentinelLoaderRuntime = runtime
	end
	if runtime.loaded[loader] or runtime.attempt then return end
	local attempt = { stage = "downloading" }
	runtime.attempt = attempt
	local previousKey = environment.script_key
	local connection
	local ok = pcall(function()
		local requester = resolve("request", "http_request") or nested("syn", "request")
		local body
		for index = 1, 3 do
			if attempt.cancelled or runtime.attempt ~= attempt then error("cancelled", 0) end
			local result
			local worker = task.spawn(function()
				result = table.pack(pcall(function()
					local url = "https://vampauth.com/v1/loaders/" .. loader .. ".lua"
					if requester then
						local success, response = pcall(requester, { Url = url, Method = "GET", Timeout = 12 })
						if success and type(response) == "table" then
							local status = tonumber(response.StatusCode or response.Status or response.status_code)
							if status and (status < 200 or status >= 300) then
								return nil, status == 408 or status == 425 or status == 429 or status >= 500
								end
							if response.Success ~= false then return response.Body or response.body, true end
						end
					end
					return game:HttpGet(url), true
				end))
			end)
			local deadline = os.clock() + 12
			while not result and not attempt.cancelled and os.clock() < deadline do task.wait(0.05) end
			if not result and type(task.cancel) == "function" then pcall(task.cancel, worker) end
			if attempt.cancelled or runtime.attempt ~= attempt then error("cancelled", 0) end
			if result and result[1] then
				local value = result[2]
				if type(value) == "string" and value:find("%S") then
					assert(#value <= 8 * 1024 * 1024, "response too large")
					body = value:gsub("^\239\187\191", "")
					break
				end
				if result[3] == false then break end
			end
			if index < 3 then task.wait(index) end
		end
		assert(body, "download failed")
		local prefix = body:match("^%s*(.)")
		assert(prefix ~= "<" and prefix ~= "{" and prefix ~= "[", "unexpected response")
		local chunk = compiler(body, "=SentinelGameLoader")
		assert(type(chunk) == "function", "compile failed")
		if attempt.cancelled or runtime.attempt ~= attempt then error("cancelled", 0) end
		local player = game:GetService("Players").LocalPlayer
		local playerDeadline = os.clock() + 15
		while not player and os.clock() < playerDeadline do
			task.wait(0.05)
			player = game:GetService("Players").LocalPlayer
		end
		assert(player, "local player unavailable")
		if attempt.cancelled or runtime.attempt ~= attempt then error("cancelled", 0) end
		local queue = resolve("queue_on_teleport", "queueonteleport", "queueteleport")
			or nested("syn", "queue_on_teleport") or nested("fluxus", "queue_on_teleport")
		if player and queue then
			local queued = false
			connection = player.OnTeleport:Connect(function(state)
				if queued or (state ~= Enum.TeleportState.Started and state ~= Enum.TeleportState.InProgress) then return end
				queued = true
				local source = "local template = " .. string.format("%q", template) .. "\n" .. template
					.. "\nresume(" .. string.format("%q, %q, %d", key, loader, universe) .. ")"
				local success, accepted = pcall(queue, source)
				queued = success and accepted ~= false
			end)
		end
		attempt.stage = "executing"
		environment.script_key = key
		chunk()
	end)
	if runtime.attempt == attempt then runtime.attempt = nil end
	if ok then
		runtime.loaded[loader] = true
		runtime.teleportConnection = connection
	else
		if connection then connection:Disconnect() end
		if attempt.stage == "executing" and environment.script_key == key then environment.script_key = previousKey end
		warn("[Sentinel Loader] Resume failed. Run the loader again to retry.")
	end
end
]=]

local function armTeleport(loader, key)
	local queue = capability("queue_on_teleport", "queueonteleport", "queueteleport")
		or nestedCapability("syn", "queue_on_teleport")
		or nestedCapability("fluxus", "queue_on_teleport")
	if not queue then
		return nil
	end
	if runtime.teleportConnection then
		runtime.teleportConnection:Disconnect()
		runtime.teleportConnection = nil
	end
	local source = "local template = " .. string.format("%q", TeleportTemplate) .. "\n" .. TeleportTemplate
		.. "\nresume(" .. string.format("%q, %q, %d", key, loader, game.GameId) .. ")"
	local queued = false
	local connection = Players.LocalPlayer.OnTeleport:Connect(function(state)
		if queued or (state ~= Enum.TeleportState.Started and state ~= Enum.TeleportState.InProgress) then
			return
		end
		queued = true
		local ok, accepted = pcall(queue, source)
		queued = ok and accepted ~= false
		if not queued then
			warn("[Sentinel Loader] Could not queue the loader for teleport.")
		end
	end)
	runtime.teleportConnection = connection
	return connection
end

local function copyLink()
	if copying or running or not ui.exists() then
		return
	end
	copying = true
	local copied = copyToClipboard(keyLink)
	ui.copy.Text = copied and "COPIED" or "GET A KEY"
	local id = notify(copied and "Link copied to clipboard." or keyLink, copied)
	task.delay(2, function()
		copying = false
		if not ui.exists() then
			return
		end
		ui.copy.Text = "GET A KEY"
		if id == messageId then
			notify("vampauth.com/sntl/flow")
		end
	end)
end

local ErrorMessages = {
	network = "Network error. Check your connection and retry.",
	timeout = "Download timed out. Please retry.",
	empty = "Server returned an empty script. Please retry.",
	tooLarge = "Downloaded script is too large.",
	response = "Server returned an unexpected response.",
	compiler = "Your executor has no compatible Lua compiler.",
	compile = "Downloaded script could not compile.",
	http401 = "Loader access denied (HTTP 401).",
	http403 = "Loader access denied (HTTP 403).",
	http404 = "Loader unavailable (HTTP 404).",
	http429 = "Too many requests. Please retry later.",
	runtime = "Script stopped with an error. Please retry.",
}

local function submitKey()
	if running or not ui.exists() then
		return
	end
	local key = normalizeKey(ui.key.Text)
	if not key then
		notify(ui.key.Text:match("^%s*$") and "Enter a key first." or "Paste a valid key.")
		ui.key:CaptureFocus()
		return
	end

	local loader = findLoader()
	if not loader then
		notify("This game isn't supported.")
		return
	end

	if runtime.loaded[loader] then
		notify("This script is already loaded.")
		return
	end
	if runtime.attempt then
		notify("A script is already loading or running.")
		return
	end
	if not capability("loadstring", "load") then
		notify(ErrorMessages.compiler)
		return
	end

	local attempt = { stage = "downloading" }
	runtime.attempt = attempt
	running = true
	ui.key:ReleaseFocus()
	ui.loading(true)
	notify("Downloading loader...", true)

	task.spawn(function()
		local previousKey = Environment.script_key
		local connection
		local function isActive()
			return runtime.attempt == attempt and not attempt.cancelled and ui.exists()
		end
		local loaded, failure = pcall(function()
			local source = httpGet("https://vampauth.com/v1/loaders/" .. loader .. ".lua", isActive)
			local run, reason = compileChunk(source)
			if not run then
				fail(reason)
			end
			if not isActive() then
				fail("cancelled")
			end
			notify("Running loader...", true)
			connection = armTeleport(loader, key)
			attempt.stage = "executing"
			Environment.script_key = key
			run()
		end)
		if runtime.attempt == attempt then
			runtime.attempt = nil
		end
		if loaded then
			runtime.loaded[loader] = true
			-- A compiled script can still fail at runtime; preserve the old saved key then.
			saveKey(key)
		else
			if connection then
				connection:Disconnect()
				if runtime.teleportConnection == connection then
					runtime.teleportConnection = nil
				end
			end
			if attempt.stage == "executing" and Environment.script_key == key then
				Environment.script_key = previousKey
			end
		end
		key = nil
		running = false
		if not ui.exists() then
			return
		end
		ui.loading(false)
		if loaded then
			notify("Loader finished.")
		else
			local code = type(failure) == "table" and failure.sentinelLoaderError or "runtime"
			if code ~= "cancelled" then
				local message = ErrorMessages[code] or "Loader download failed. Please retry."
				notify(message)
				warn("[Sentinel Loader] " .. message)
			end
		end
	end)
end

ui.connect(ui.copy.Activated, copyLink)
ui.connect(ui.submit.Activated, submitKey)
ui.connect(ui.key.FocusLost, function(enterPressed)
	if enterPressed then
		submitKey()
	end
end)
