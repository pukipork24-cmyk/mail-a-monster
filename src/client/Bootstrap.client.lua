--!strict
local UIController = require(script.Parent.UIController)
local controller = UIController.new()
controller:start()
script.Destroying:Connect(function()
	controller:destroy()
end)
