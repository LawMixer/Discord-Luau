local DiscordSettings = require("DiscordSettings")

local Construct = require("../Utils/Construct")

local DiscordGateway = require("Network/DiscordGateway")
local DiscordShard = require("Network/DiscordShard")

local DiscordEndpoints = require("../Enums/DiscordEndpoints")
local WebsocketEvents = require("../Enums/WebsocketEvents")
local DiscordEvents = require("../Enums/DiscordEvents")
local WebsocketOperationCodes = require("../Enums/WebsocketOperationCodes")
local WebsocketOperationKeys = require("../Enums/WebsocketOperationKeys")

local EndpointCache = require("Internal/EndpointCache")
local DiscordCache = require("Internal/DiscordCache")
local DiscordUser = require("Internal/DiscordUser")
local DiscordGuild = require("Internal/DiscordGuild")
local DiscordChannel = require("Internal/DiscordChannel")
local DiscordTextChannel = require("Internal/DiscordTextChannel")
local DiscordVoiceChannel = require("Internal/DiscordVoiceChannel")
local DiscordMessage = require("Internal/DiscordMessage")
local DiscordApplication = require("Internal/DiscordApplication")
local DiscordInteraction = require("Internal/DiscordInteraction")

local Console = require("../Vendor/Console")
local Future = require("../Vendor/Future")
local Signal = require("../Vendor/Signal")

local Task = require("../Std/Task")

local CONCURRENT_IDENTIFY_YIELD = 5

--[=[
	@class DiscordClient

	The base class that implements the various properties, methods and events that developers can use to interact with the Discord API.

	```lua
		local DiscordLuau = require("../Submodules/DiscordLuau")

		local DiscordSettings = DiscordLuau.DiscordSettings.new("BOT TOKEN")
		local DiscordClient = DiscordLuau.DiscordClient.new(DiscordSettings)

		...
	```
]=]
local DiscordClient = {}

DiscordClient.Prototype = {}
DiscordClient.Interface = {}

DiscordClient.Prototype.type = "DiscordClient"

--[=[
	@method connectAsync
	@within DiscordClient

	@return Future

	Connect the current DiscordClient to the Discord API

	```lua
		local DiscordClient = DiscordLuau.DiscordClient.new(DiscordSettings)

		DiscordClient:connectAsync():after(function()
			print("Connected to the Discord API!")
		end)
	```
]=]
function DiscordClient.Prototype.connectAsync(self: DiscordClient)
	return Future.try(function()
		self.discordGateway:setEndpointCache(DiscordEndpoints.BotGateway, EndpointCache.new(10))

		local data = self.discordGateway:getAsync(DiscordEndpoints.BotGateway):await()
		local websocketVersion = self.discordGateway:getApiVersion()

		self.websocketUrl = `{data.url}/?v={websocketVersion}` :: string
		self.maxConcurrency = data.sessionStartLimit.maxConcurrency :: number
		self.shardCount = data.shards :: number

		for shardId = 1, self.shardCount do
			self.discordShards[shardId] = DiscordShard.new(self, shardId - 1)
		end

		for bucketIndex = 1, self.shardCount, self.maxConcurrency do
			for shardId = bucketIndex, (bucketIndex - 1) + self.maxConcurrency do
				self.discordShards[shardId]:connectAsync(self.websocketUrl)
			end

			if self.shardCount > self.maxConcurrency then
				Task.wait(CONCURRENT_IDENTIFY_YIELD)
			end
		end

		for shardId = 1, self.shardCount do
			local shard = self.discordShards[shardId]

			shard.onEvent:connect(function(eventName, data)
				if eventName == WebsocketEvents.Ready then
					--[=[
						@prop discordUser DiscordUser
						@within DiscordClient
					]=]
					self.discordUser = DiscordUser.new(self, data.user)
					--[=[
						@prop discordApplication DiscordApplication
						@within DiscordClient
					]=]
					self.discordApplication = DiscordApplication.new(self, data.application)

					self.onEvent:fire(DiscordEvents.Ready)
				elseif eventName == WebsocketEvents.MessageCreate then
					local discordMessage = DiscordMessage.new(self, data)

					self.onEvent:fire(DiscordEvents.Message, discordMessage)
				elseif eventName == WebsocketEvents.MessageUpdate then
					local discordMessage = DiscordMessage.new(self, data)

					self.onEvent:fire(DiscordEvents.MessageChanged, discordMessage)
				elseif eventName == WebsocketEvents.MessageDeleted then
					local discordMessage = DiscordMessage.new(self, data)

					self.onEvent:fire(DiscordEvents.MessageDeleted, discordMessage)
				elseif eventName == WebsocketEvents.InteractionCreate then
					local discordInteraction = DiscordInteraction.new(self, data)

					self.onEvent:fire(DiscordEvents.Interaction, discordInteraction)
				elseif eventName == WebsocketEvents.MessageBulkDeleted then
					self.onEvent:fire(DiscordEvents.MessageBulkDeleted, data)
				elseif eventName == WebsocketEvents.ChannelCreate then
					local discordChannel = DiscordChannel.new(self, data)

					self.onEvent:fire(DiscordEvents.ChannelCreate, discordChannel)
				elseif eventName == WebsocketEvents.ChannelUpdate then
					local discordChannel = DiscordChannel.new(self, data)

					self.onEvent:fire(DiscordEvents.ChannelUpdate, discordChannel)
				elseif eventName == WebsocketEvents.ChannelDeleted then
					local discordChannel = DiscordChannel.new(self)

					self.onEvent:fire(DiscordEvents.ChannelDelete, discordChannel)
				elseif eventName == WebsocketEvents.UserUpdated then
					self.discordUser = DiscordUser.new(self, data.user)
					
					self.onEvent:fire(DiscordEvents.UserUpdated, self.discordUser)
				elseif eventName == WebsocketEvents.ChannelPinsUpdate then
					self.onEvent:fire(DiscordEvents.ChannelPinsUpdate, data)
				elseif eventName == WebsocketEvents.GuildCreate then
					local discordGuild = DiscordGuild.new(self, data)

					self.onEvent:fire(DiscordEvents.GuildCreate, discordGuild)
				elseif eventName == WebsocketEvents.GuildUpdate then
					local discordGuild = DiscordGuild.new(self, data)

					self.onEvent:fire(DiscordEvents.GuildCreate, discordGuild)
				elseif eventName == WebsocketEvents.GuildDeleted then
					local discordGuild = DiscordGuild.new(self, data)

					self.onEvent:fire(DiscordEvents.GuildCreate, discordGuild)
				elseif eventName == WebsocketEvents.GuildMemberBanned then
					data.user = DiscordUser.new(self, data.user)

					self.onEvent:fire(DiscordEvents.GuildMemberBanned, data)
				elseif eventName == WebsocketEvents.GuildMemberUnbanned then
					data.user = DiscordUser.new(self, data.user)

					self.onEvent:fire(DiscordEvents.GuildMemberBanned, data)
				elseif eventName == WebsocketEvents.GuildMemberJoined then
					data.user = DiscordUser.new(self, data.user)

					self.onEvent:fire(DiscordEvents.GuildMemberJoined, data)
				elseif eventName == WebsocketEvents.GuildMemberLeft then
					data.user = DiscordUser.new(self, data.user)

					self.onEvent:fire(DiscordEvents.GuildMemberLeft, data)
				elseif eventName == WebsocketEvents.GuildMemberUpdated then
					data.user = DiscordUser.new(self, data.user)

					self.onEvent:fire(DiscordEvents.GuildMemberUpdated, data)
				else
					self.reporter:debug(`Unknown Event: '{eventName}'`)
				end
			end)
		end
	end)
end

--[=[
	@method fetchGuildAsync
	@within DiscordClient

	@return Future
]=]
function DiscordClient.Prototype.fetchGuildAsync(self: DiscordClient, guildId: string): Future.Future<DiscordGuild.DiscordGuild>
	return Future.try(function()
		local rawGuildData = self.discordGateway:getAsync(string.format(DiscordEndpoints.BotGetGuild, guildId)):await()

		return DiscordGuild.new(self, rawGuildData)
	end)
end

--[=[
	@method fetchChannelAsync
	@within DiscordClient

	@return Future
]=]
function DiscordClient.Prototype.fetchChannelAsync(self: DiscordClient, channelId: string): Future.Future<DiscordChannel.DiscordChannel>
	return Future.try(function()
		local rawChannelData = self.discordGateway:getAsync(string.format(DiscordEndpoints.BotGetChannel, channelId)):await()

		return DiscordChannel.new(self, rawChannelData) :: DiscordChannel.DiscordChannel
	end)
end

--[=[
	@method updatePresenceAsync
	@within DiscordClient

	@return Future
]=]
function DiscordClient.Prototype.updatePresenceAsync(self: DiscordClient, discordPresence): Future.Future<boolean>
	return Future.try(function()
		for shardId = 1, self.shardCount do
			(self.discordShards :: { DiscordShard.DiscordShard })[shardId].discordWebsocket:sendAsync(
				{
					[WebsocketOperationKeys.OperationCode] = WebsocketOperationCodes.PresenseUpdate,
					[WebsocketOperationKeys.Data] = discordPresence:toJSONObject(),
				}
			):await()
		end

		return true
	end)
end

--[=[
	@method on
	@within DiscordClient

	@return Connection
]=]
function DiscordClient.Prototype.on(self: DiscordClient, targetEventName: string, eventCallback: (...any) -> ())
	return self.onEvent:connect(function(eventName: string, ...)
		if eventName ~= targetEventName then
			return
		end

		eventCallback(...)
	end)
end

--[=[
	@method setVerbose
	@within DiscordClient
]=]
function DiscordClient.Prototype.setVerbose(self: DiscordClient, verbose: boolean)
	Console.setGlobalLogLevel(verbose and Console.LogLevel.debug or Console.LogLevel.warn)
end

--[=[
	@function new
	@within DiscordClient

	@return DiscordClient

	Constructor function for the Discord Client, this is where you'll be able to instantiate a Discord Client object.

	```lua
		local DiscordClient = DiscordLuau.DiscordClient.new(DiscordSettings)

		DiscordClient:connectAsync():after(function()
			print("Connected to the Discord API!")
		end)
	```
]=]
function DiscordClient.Interface.new(discordSettings: DiscordSettings.DiscordSettings)
	local self = (Construct({
		--[=[
			@prop discordSettings DiscordSettings
			@within DiscordClient
		]=]
		discordSettings = discordSettings,

		--[=[
			@prop discordCache DiscordCache
			@within DiscordClient
		]=]
		discordCache = DiscordCache.new(),

		--[=[
			@prop reporter Reporter
			@within DiscordClient
		]=]
		reporter = Console.new("🎮 DiscordClient"),

		--[=[
			@prop websocketUrl string
			@within DiscordClient
		]=]
		websocketUrl = "",

		--[=[
			@prop shardCount number
			@within DiscordClient
		]=]
		shardCount = 0,

		--[=[
			@prop maxConcurrency number
			@within DiscordClient
		]=]
		maxConcurrency = 0,

		--[=[
			@prop discordShards { DiscordShard }
			@within DiscordClient
		]=]
		discordShards = {},

		--[=[
			@prop onEvent Signal
			@within DiscordClient
		]=]
		onEvent = Signal.new(),
	}, DiscordClient.Prototype) :: unknown) :: DiscordClient

	--[=[
		@prop discordGateway DiscordGateway
		@within DiscordClient
	]=]
	self.discordGateway = DiscordGateway.new(self)

	return self
end

Console.setGlobalLogLevel(Console.LogLevel.warn)

export type DiscordClient = typeof(DiscordClient.Prototype) & {
	discordGateway: DiscordGateway.DiscordGateway,
	discordSettings: DiscordSettings.DiscordSettings,
	discordCache: DiscordCache.DiscordCache,

	websocketUrl: string,
	shardCount: number,
	maxConcurrency: number,

	onEvent: Signal.Signal<string, { [any]: any }?>,

	reporter: Console.Console,

	discordShards: { DiscordShard.DiscordShard },

	discordUser: DiscordUser.DiscordUser,
	discordApplication: DiscordApplication.DiscordApplication,
}

return DiscordClient.Interface