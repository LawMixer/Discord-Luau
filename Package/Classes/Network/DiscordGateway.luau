local Future = require("../../Vendor/Future")
local Console = require("../../Vendor/Console")

local Construct = require("../../Utils/Construct")

local HTTPRatelimit = require("HTTPRatelimit")
local HTTPScheduler = require("HTTPScheduler")

local EventIn = require("../Middleware/EventIn")
local EventOut = require("../Middleware/EventOut")

local Serde = require("../../Std/Serde")
local Net = require("../../Std/Net")
local Task = require("../../Std/Task")

local DISCORD_API_VERSION = 9

local BASE_DISCORD_APP_URL = "https://discord.com"
local BASE_DISCORD_APP_API_PREFIX = "api"

--[=[
	@class Network.DiscordGateway

	(sorry I will add docs for this lol, just haven't got around to it yet!)
]=]
local DiscordGateway = {}

DiscordGateway.Interface = {}
DiscordGateway.Prototype = {}

DiscordGateway.Prototype.type = "DiscordGateway"

function DiscordGateway.Prototype.parseErrors(self: DiscordGateway, errorTable: { [any]: any }, source: string?, depth: number?)
	local _source = source or ""
	local _depth = depth or 0

	for index, value in errorTable do
		if index == "_errors" then
			for _, errorObject in value do
				_source ..= `{string.rep(" ", _depth)}{errorObject.code}: {errorObject.message}\n`
			end
		else
			_source ..= `{string.rep(" ", _depth)}{index}:\n{self:parseErrors(value, _source, _depth + 1)}\n`
		end
	end

	return _source
end

function DiscordGateway.Prototype.parseDiscordAPIErrors(self: DiscordGateway, api: string, networkResponse: Net.FetchResponse)
	local success, messageDecoded = pcall(function()
		return Serde.decode("json", networkResponse.body)
	end)

	if success then
		local discordErrorString = ""

		if messageDecoded.errors then
			discordErrorString = self:parseErrors(messageDecoded.errors)
		end

		return `Discord API Error - {messageDecoded.code} ({messageDecoded.message}): \n\nAPI: {api}\n\nTRACE:\n{discordErrorString}`
	end

	return `Discord HTTP Error - {networkResponse.statusCode} ({networkResponse.statusMessage}): \n{networkResponse.body}`
end

function DiscordGateway.Prototype.requestAsync(self: DiscordGateway, api: string, method: ("DELETE" | "GET" | "HEAD" | "OPTIONS" | "PATCH" | "POST" | "PUT"), data: { [any]: any }?)
	return Future.try(function()
		return self.discordScheduler:addTask(function()
			local ratelimitApi = string.gsub(api, "%d+", "-")

			if self.endpointRateLimits[ratelimitApi] and self.endpointRateLimits[ratelimitApi]:isConsumed() then
				while self.endpointRateLimits[ratelimitApi]:isConsumed() do
					Task.wait()
				end
			end

			local networkResponse = Net.request({
				url = `{BASE_DISCORD_APP_URL}/{BASE_DISCORD_APP_API_PREFIX}/v{DISCORD_API_VERSION}/{api}`,
				method = method,
				headers = {
					["authorization"] = `Bot {self.discordClient.discordSettings.discordToken}`,
					["content-type"] = "application/json"
				},
				body = data and Serde.encode("json", self.gatewayEventOut:processJSON(data))
			})

			self.reporter:debug(`{method} Async to '{api}': {networkResponse.statusCode} - {networkResponse.statusMessage}`)

			local ratelimitLimit = tonumber(networkResponse.headers["x-ratelimit-limit"])
			local ratelimitRemaining = tonumber(networkResponse.headers["x-ratelimit-remaining"])
			local ratelimitResetAfter = tonumber(networkResponse.headers["x-ratelimit-reset-after"])

			if ratelimitLimit and ratelimitRemaining and ratelimitResetAfter then
				if not self.endpointRateLimits[ratelimitApi] then
					self.endpointRateLimits[ratelimitApi] = (HTTPRatelimit.new(
						ratelimitLimit,
						ratelimitRemaining
					) :: unknown) :: HTTPRatelimit.HTTPRatelimit
				end

				self.endpointRateLimits[ratelimitApi]:setRemaining(ratelimitRemaining)
				self.endpointRateLimits[ratelimitApi]:resetAfter(ratelimitResetAfter + 1)

				self.reporter:debug(`{method} Rate Limit '{ratelimitLimit - ratelimitRemaining}/{ratelimitLimit}, resetting in {ratelimitResetAfter}'`)
			end

			if not networkResponse.ok then
				error(self:parseDiscordAPIErrors(api, networkResponse))
			end

			if networkResponse.body == "" then
				return
			else
				return self.gatewayEventIn:processJSON(Serde.decode("json", networkResponse.body))
			end
		end)
	end)
end

function DiscordGateway.Prototype.getAsync(self: DiscordGateway, api: string)
	return Future.try(function()
		local cache = self:getEndpointCache(api)
		local cacheValue = cache and cache:get()

		if cacheValue then
			return cacheValue
		end

		local response = self:requestAsync(api, "GET"):await()

		if cache then
			cache:set(response)
		end

		return response
	end)
end

function DiscordGateway.Prototype.postAsync(self: DiscordGateway, api: string, data: { [any]: any })
	return self:requestAsync(api, "POST", data)
end

function DiscordGateway.Prototype.deleteAsync(self: DiscordGateway, api: string, data: { [any]: any })
	return self:requestAsync(api, "DELETE", data)
end

function DiscordGateway.Prototype.patchAsync(self: DiscordGateway, api: string, data: { [any]: any })
	return self:requestAsync(api, "PATCH", data)
end

function DiscordGateway.Prototype.setEndpointCache(self: DiscordGateway, endpoint: string, cache: { [any]: any })
	self.endpointCaches[endpoint] = cache
end

function DiscordGateway.Prototype.getEndpointCache(self: DiscordGateway, endpoint: string)
	return self.endpointCaches[endpoint]
end

function DiscordGateway.Prototype.getApiVersion(self: DiscordGateway)
	return DISCORD_API_VERSION
end

function DiscordGateway.Interface.new(discordClient: any)
	return Construct({
		discordClient = discordClient,
		discordScheduler = HTTPScheduler.new(1),

		gatewayEventIn = EventIn.new(),
		gatewayEventOut = EventOut.new(),

		reporter = Console.new("🌉 DiscordGateway"),

		endpointRateLimits = {} :: { [string]: HTTPRatelimit.HTTPRatelimit },
		endpointCaches = {} :: { [string]: { [any]: any } }
	}, DiscordGateway.Prototype)
end

export type DiscordGateway = typeof(DiscordGateway.Interface.new())

return DiscordGateway.Interface