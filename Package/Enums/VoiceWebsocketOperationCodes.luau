-- https://discord.com/developers/docs/topics/opcodes-and-status-codes#gateway-gateway-opcodes

return {
	["Identify"] = 0,
	["SelectProtocol"] = 1,
	["Ready"] = 2,
	["Heartbeat"] = 3,
	["SessionDescription"] = 4,
	["Speaking"] = 5,
	["HeartbeatACK"] = 6,
	["Resume"] = 7,
	["Hello"] = 8,
	["Resumed"] = 9,
	["ClientDisconnect"] = 13
}