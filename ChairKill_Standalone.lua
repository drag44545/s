local Players = game:GetService("Players")

local LocalPlayer = Players.LocalPlayer

local Library = loadstring(
	game:HttpGet("https://raw.githubusercontent.com/deividcomsono/Obsidian/refs/heads/main/Library.lua")
)()

local Options = Library.Options

local DEFAULTS = {
	Radius = 2.5,
	Speed = 60,
	Interval = 0.08,
	MaxSeconds = 60,
	GrabTimeout = 300,
	LeashFactor = 3,
	VerticalBias = 1.5,
}

local state = {
	running = false,
}
local StatusLabel

local function setStatus(text)
	if StatusLabel then
		pcall(function()
			StatusLabel:SetText(text)
		end)
	end
end

local function notify(title, body, time)
	pcall(function()
		Library:Notify({
			Title = title,
			Description = body,
			Time = time or 4,
		})
	end)
end

local ghp = gethiddenproperty

if type(ghp) ~= "function" then
	ghp = nil
end

local function isnetworkowner(part)
	if not ghp or not part then
		return nil
	end
	local ok, value = pcall(ghp, part, "NetworkOwnerV3")
	if not ok then
		return nil
	end
	return value == -1 or value == 4
end

local function grabAttachment()
	local character = LocalPlayer.Character
	local collision = character and character:FindFirstChild("CollisionPart")
	return collision and collision:FindFirstChild("CartTargetAttachment") or nil
end

local function findPropByName(misc)
	for _, child in ipairs(misc:GetChildren()) do
		local name = child.Name
		local isChair = string.sub(name, -11) == "OfficeChair"
		local isCart = name == "ShoppingCart" or name == "TV_Stand"
		if isChair or isCart then
			local base = child:FindFirstChild("Base")
			local collider = child:FindFirstChild("Collider")
			if base and collider then
				return child, base, collider, "name"
			end
		end
	end
	return nil
end

local function findPropByGrab(character)
	local collision = character:FindFirstChild("CollisionPart")
	if not collision then
		return nil
	end
	local function otherEnd(constraint)
		local ok, isAlign = pcall(function()
			return constraint:IsA("AlignPosition") or constraint:IsA("AlignOrientation")
		end)
		if not ok or not isAlign then
			return nil
		end
		local a0, a1 = constraint.Attachment0, constraint.Attachment1
		if not (a0 and a1) then
			return nil
		end
		local function inside(attachment)
			local part = attachment.Parent
			return part and part:IsDescendantOf(character)
		end
		if inside(a0) and not inside(a1) then
			return a1
		end
		if inside(a1) and not inside(a0) then
			return a0
		end
		return nil
	end
	local function fromAttachment(side)
		local part = side.Parent
		if not part then
			return nil
		end
		local model = part:FindFirstAncestorWhichIsA("Model")
		while model do
			local collider = model:FindFirstChild("Collider")
			if collider then
				return model, model:FindFirstChild("Base") or part, collider, "grab link"
			end
			model = model:FindFirstAncestorWhichIsA("Model")
		end
		return nil
	end
	local function scan(container)
		for _, descendant in ipairs(container:GetDescendants()) do
			local side = otherEnd(descendant)
			if side then
				local model, base, collider, how = fromAttachment(side)
				if model then
					return model, base, collider, how
				end
			end
		end
		return nil
	end
	local model, base, collider, how = scan(collision)
	if model then
		return model, base, collider, how
	end
	model, base, collider, how = scan(character)
	if model then
		return model, base, collider, how
	end
	local misc = workspace:FindFirstChild("Misc")
	if misc then
		model, base, collider, how = scan(misc)
		if model then
			return model, base, collider, how
		end
	end
	return scan(workspace)
end

local function findProp()
	local character = LocalPlayer.Character
	if character then
		local prop, base, collider, how = findPropByGrab(character)
		if prop then
			return prop, base, collider, how
		end
	end
	local misc = workspace:FindFirstChild("Misc")
	if misc then
		return findPropByName(misc)
	end
	return nil
end

local function resolveTarget()
	local value = Options.Target and Options.Target.Value
	if typeof(value) == "Instance" then
		return value
	elseif type(value) == "string" and value ~= "" then
		return Players:FindFirstChild(value)
	end
	return nil
end

local function runLoop(prop, base, collider, player)
	local drive = collider
	if isnetworkowner(base) and not isnetworkowner(collider) then
		drive = base
	end
	if collider.Anchored then
		pcall(function()
			collider.Anchored = false
		end)
	end
	local oldPivot = prop:GetPivot()
	local started = os.clock()
	local nextPlace = started
	local lastHealth = nil
	local contacts, damage, placements = 0, 0, 0
	while state.running and os.clock() - started < DEFAULTS.MaxSeconds do
		if not prop.Parent then
			print("[chair] prop disappeared")
			break
		end
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if not root or not humanoid or humanoid.Health <= 0 then
			break
		end
		local radius = Options.Radius.Value
		local speed = Options.Speed.Value
		local interval = Options.Interval.Value
		local now = os.clock()
		local distance = (drive.Position - root.Position).Magnitude
		if now >= nextPlace or distance > radius * DEFAULTS.LeashFactor then
			local angle = math.random() * math.pi * 2
			local offset = Vector3.new(
				math.cos(angle) * radius,
				DEFAULTS.VerticalBias,
				math.sin(angle) * radius
			)
			pcall(function()
				prop:PivotTo(CFrame.new(root.Position + offset))
			end)
			placements += 1
			nextPlace = now + interval
		end
		local toTarget = root.Position - drive.Position
		if toTarget.Magnitude > 0.05 then
			pcall(function()
				drive.AssemblyLinearVelocity = toTarget.Unit * speed
			end)
		end
		local health = humanoid.Health
		if lastHealth and health < lastHealth then
			local delta = lastHealth - health
			contacts += 1
			damage += delta
			print(string.format(
				"[chair] hit %d  -%d  health %.0f  (placements %d)",
				contacts,
				delta,
				health,
				placements
			))
		end
		lastHealth = health
		task.wait()
	end
	pcall(function()
		prop:PivotTo(oldPivot)
	end)
	return contacts, damage, placements
end

local function worker()
	while state.running do
		if not grabAttachment() then
			setStatus("waiting for a chair grab")
			local waited = 0
			while state.running and not grabAttachment() and waited < DEFAULTS.GrabTimeout do
				task.wait(0.2)
				waited += 0.2
			end
			if not state.running then
				break
			end
			if not grabAttachment() then
				notify("Chair", "No chair grab in five minutes.", 5)
				break
			end
		end
		local player = resolveTarget()
		if not player then
			notify("Chair", "Pick a player first.", 5)
			break
		end
		local prop, base, collider, how = findProp()
		if not prop then
			notify("Chair", "Grabbed, but the prop could not be resolved.", 5)
			print("[chair] prop resolution failed")
			break
		end
		print(string.format(
			"[chair] prop %s via %s  (collider owned=%s)",
			prop:GetFullName(),
			how,
			tostring(isnetworkowner(collider))
		))
		setStatus("running on " .. player.Name)
		local contacts, damage, placements = runLoop(prop, base, collider, player)
		print(string.format(
			"[chair] finished: %d contacts, %d damage, %d placements",
			contacts,
			damage,
			placements
		))
		if contacts > 0 then
			notify("Chair", string.format("%d hits, %d damage.", contacts, damage), 5)
		else
			notify("Chair", "No contacts landed.", 5)
		end
		if state.running then
			setStatus("waiting for release")
			while state.running and grabAttachment() do
				task.wait(0.5)
			end
		end
	end
	state.running = false
	setStatus("idle")
end

local function startWorker()
	if state.running then
		return
	end
	state.running = true
	task.spawn(worker)
end

local function stopWorker()
	state.running = false
	setStatus("idle")
end

local Window = Library:CreateWindow({
	Title = "Chair Kill",
	Footer = "",
	NotifySide = "Right",
	ShowCustomCursor = false,
	AutoShow = true,
	Center = true,
	TabPadding = 3,
	MenuFadeTime = 0,
	CornerRadius = 6,
	ToggleKeybind = Enum.KeyCode.RightShift,
})

local Tab = Window:AddTab("Chair Kill", "target")

local TargetBox = Tab:AddLeftGroupbox("Target")

local LoopBox = Tab:AddRightGroupbox("Loop")
TargetBox:AddDropdown("Target", {
	Text = "Player",
	SpecialType = "Player",
	ExcludeLocalPlayer = true,
	Searchable = true,
	Callback = function()
		local player = resolveTarget()
		if player then
			setStatus("target: " .. player.Name)
		end
	end,
})
TargetBox:AddButton("Refresh", function()
	local player = resolveTarget()
	if player then
		setStatus("target: " .. player.Name)
		notify("Chair", "Target: " .. player.Name, 3)
	else
		notify("Chair", "No player selected.", 3)
	end
end)
TargetBox:AddLabel("Pick who the chair goes after, then grab a chair.", true)
LoopBox:AddToggle("ChairKill", {
	Text = "Chair Kill",
	Default = false,
	Tooltip = "Re-places a grabbed chair around the target until it lands.",
	Callback = function(value)
		if value then
			startWorker()
		else
			stopWorker()
		end
	end,
})
LoopBox:AddSlider("Radius", {
	Text = "Place Radius",
	Min = 1,
	Max = 8,
	Default = DEFAULTS.Radius,
	Rounding = 1,
	Suffix = " studs",
})
LoopBox:AddSlider("Speed", {
	Text = "Approach Speed",
	Min = 20,
	Max = 200,
	Default = DEFAULTS.Speed,
	Rounding = 0,
})
LoopBox:AddSlider("Interval", {
	Text = "Re-place Interval",
	Min = 0.02,
	Max = 0.5,
	Default = DEFAULTS.Interval,
	Rounding = 2,
	Suffix = "s",
})
LoopBox:AddDivider()
StatusLabel = LoopBox:AddLabel("idle", true)

setStatus("idle")

print("[chair] loaded. pick a player, grab a chair, toggle on.")
