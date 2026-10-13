--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Theme = require(script.Parent.Theme)
local MonsterFactory = require(ReplicatedStorage:WaitForChild("MailAMonster"):WaitForChild("Shared"):WaitForChild("MonsterFactory"))

local Widgets = {}

function Widgets.create(className: string, properties: {[string]: any}, parent: Instance?): any
	local instance = Instance.new(className)
	for key, value in pairs(properties) do
		(instance :: any)[key] = value
	end
	instance.Parent = parent
	return instance
end

function Widgets.corner(parent: Instance, radius: number?)
	Widgets.create("UICorner", { CornerRadius = UDim.new(0, radius or 14) }, parent)
end

function Widgets.padding(parent: Instance, pixels: number)
	Widgets.create("UIPadding", {
		PaddingTop = UDim.new(0, pixels), PaddingBottom = UDim.new(0, pixels),
		PaddingLeft = UDim.new(0, pixels), PaddingRight = UDim.new(0, pixels),
	}, parent)
end

function Widgets.list(parent: Instance, gap: number?, horizontal: boolean?)
	return Widgets.create("UIListLayout", {
		Padding = UDim.new(0, gap or 10), SortOrder = Enum.SortOrder.LayoutOrder,
		FillDirection = if horizontal then Enum.FillDirection.Horizontal else Enum.FillDirection.Vertical,
		HorizontalAlignment = Enum.HorizontalAlignment.Left,
	}, parent)
end

function Widgets.label(parent: Instance, value: string, size: number?, color: Color3?): TextLabel
	return Widgets.create("TextLabel", {
		Name = "Text", BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y, Text = value, TextSize = size or 17,
		Font = Enum.Font.GothamMedium, TextColor3 = color or Theme.Ink,
		TextWrapped = true, TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
	}, parent)
end

function Widgets.button(parent: Instance, value: string, callback: (() -> ())?, secondary: boolean?, disabledReason: string?): TextButton
	local button = Widgets.create("TextButton", {
		Name = "Button", Size = UDim2.new(1, 0, 0, 48), TextWrapped = true,
		Text = if disabledReason then value .. " · " .. disabledReason else value,
		Font = Enum.Font.GothamMedium, TextSize = 16,
		TextColor3 = if secondary or disabledReason then Theme.Ink else Theme.White,
		BackgroundColor3 = if disabledReason then Theme.Line elseif secondary then Theme.Sky else Theme.Teal,
		AutoButtonColor = disabledReason == nil, Selectable = disabledReason == nil,
		Active = disabledReason == nil,
	}, parent)
	Widgets.corner(button, 12)
	Widgets.padding(button, 6)
	if callback and not disabledReason then
		button.Activated:Connect(callback)
	end
	return button
end

function Widgets.card(parent: Instance, heading: string?): Frame
	local frame = Widgets.create("Frame", {
		Name = "Card", Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundColor3 = Theme.Paper, BorderSizePixel = 0,
	}, parent)
	Widgets.corner(frame)
	Widgets.padding(frame, 14)
	Widgets.list(frame, 10)
	if heading then Widgets.label(frame, heading, 21) end
	return frame
end

function Widgets.row(parent: Instance, height: number?): Frame
	local frame = Widgets.create("Frame", {
		Size = UDim2.new(1, 0, 0, height or 48), BackgroundTransparency = 1,
	}, parent)
	Widgets.list(frame, 8, true)
	return frame
end

function Widgets.pair(parent: Instance, leftText: string, leftAction: () -> (), rightText: string, rightAction: () -> ())
	local row = Widgets.row(parent)
	local left = Widgets.button(row, leftText, leftAction)
	left.Size = UDim2.new(0.5, -4, 1, 0)
	local right = Widgets.button(row, rightText, rightAction, true)
	right.Size = UDim2.new(0.5, -4, 1, 0)
	return row
end

function Widgets.portrait(parent: Instance, monster: any, size: number?): (ViewportFrame, Model?)
	local viewport = Widgets.create("ViewportFrame", {
		Name = "MonsterPortrait", Size = UDim2.new(1, 0, 0, size or 180),
		BackgroundColor3 = Theme.Lavender, BorderSizePixel = 0,
		Ambient = Color3.fromRGB(205, 205, 205), LightColor = Color3.fromRGB(255, 248, 222),
		LightDirection = Vector3.new(-1, -1, -1),
	}, parent)
	Widgets.corner(viewport, 16)
	local world = Widgets.create("WorldModel", {}, viewport)
	local success, model = pcall(MonsterFactory.create, monster, 1)
	if not success then
		Widgets.label(viewport, monster.name or "Little monster", 20)
		warn("MAIL A MONSTER portrait unavailable", model)
		return viewport, nil
	end
	model.Parent = world
	local camera = Widgets.create("Camera", { FieldOfView = 32, CFrame = CFrame.lookAt(Vector3.new(7, 5, -13), Vector3.new(0, 2.5, 0)) }, viewport)
	viewport.CurrentCamera = camera
	return viewport, model
end

return Widgets
