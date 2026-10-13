--!strict
-- Server-only configuration. Never accept backend selection from a client.
return {
	Mode = "Simulation", -- Honored ONLY in Roblox Studio. Published servers use Live.
	LiveNamespace = "MAM_TEST_V1", -- Publish tests into a separate private TEST universe.
	EnableStudioDeveloperCommands = true,
	SnapshotInterval = 15,
}
