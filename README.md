tptmp
=====

The Powder Toy Multiplayer Script

Server Usage
------------
1. `lua server.lua`

Client Usage
------------

####Loading the client
1. Move `client.lua` to the same directory as TPT.
2. Open the TPT console by pressing the `~`.
3. Load the client by typing: `dofile("client.lua")`.

####Connecting to a server
1. Press the icon on the left that looks like this: `<<`.
2. In the window that pops-up, type `/connect`.

####Joining other channels
Each server can have multiple channels.
To join/create a channel use this command: `/join <channel>`.
If you don't join another channel, you will stay in the default one.

###Client Commands
```
/me <message>           say something in 3rd person
/connect [ip] [port]    connect to a TPT multiplayer server, or no args to connect to the default one
/quit                   disconnect from the server
/disconnect             alias for /quit
/join <channel>         join a room on the server
/kick <nick> <reason>   kick a user, only works if you have been in a channel the longest
/list                   list all of the commands
/help <command>         display information on a command
/sync                   syncs your screen to everyone else in the room
```
