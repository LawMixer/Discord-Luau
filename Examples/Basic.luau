local DiscordLuau = require("..")
local Env = require("../.env")


client = DiscordLuau.DiscordClient(
    DiscordLuau.DiscordIntents.Intents.GuildMembers, 
    "Token"
)

client.Events.Ready:Connect(function()
    print(`This bot is owned by {client.owner}`)
end)


client.Events.MessageCreate:Connect(function(event: EventInteraction)
    print(`message received: {event.message.content}`)
end)

client.Commands:AddCommand("name", "description", function(event: DiscordLuau.DiscordInteraction)
    print(`{event.user.username} have ran the command.`)
end)


client:Start()