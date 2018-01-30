tptmp
=====

The Powder Toy Multiplayer Script

Server Usage
------------

#### Running the server
1. Edit `config.lua` as needed
2. run the command `lua server.lua`

#### Creating hooks
Create a .lua file in hooks/

Add server side commands using `function commandHooks.<name>(client, msg, msgsplit)`
msg is the full message after the command, and msgsplit is a table of all the space separated words.

Add event hooks using `function serverHooks.<uniquefunctionname>(client, cmd, msg)`
cmd is the event number, and msg is a special message that may be attached to it. Events are the same as the numbers handled in server.lua, with the special event -1 for quitting, and -2 for leaving a room.

#### Default hooks
badwords.lua kicks users off the server for using words in the predefined badwords list inside of messages or actions.
commands.lua keeps track of the last time a user was online, for use in /seen.
motd.lua sends a motd whenever any user joins a channel and motd[<channel>] exists.

### Server Commands
```
/slist                  Prints a list of server side commands.
/shelp <command>        Prints help for a command.
/online                 Prints how many players are online and how many rooms there are.
/msg <user> <message>   Sends a private message to a user.
/motd <motd>            Sets the motd for a channel, if you were the first to join.
/invite <user>          Invites a user to a channel and sends a message asking them to join.
/private                Toggles a channel's private status. Use /invite to invite users.
/seen <user>            Tells you the amount of time since a user was last online.
```

Client Usage
------------

#### Loading the client
1. Move `client.lua` to the same directory as TPT.
2. Open the TPT console by pressing the `~`.
3. Load the client by typing: `dofile("client.lua")`.

#### Connecting to a server
1. Press the icon on the left that looks like this: `<<`.
2. In the window that pops-up, type `/connect`.

#### Joining other channels
Each server can have multiple channels.
To join/create a channel use this command: `/join <channel>`.
If you don't join another channel, you will stay in the default one.

### Client Commands
```
/me <message>           Say something in 3rd person.
/connect [ip] [port]    Connect to a TPT multiplayer server, or no args to connect to the default one.
/quit                   Disconnect from the server.
/disconnect             Alias for /quit.
/join <channel>         Join a room on the server.
/kick <nick> [reason]   Kick a user, only works if you have been in a channel the longest.
/list                   List all of the commands.
/help <command>         Display information on a command.
/sync                   Syncs your screen to everyone else in the room.
/size <width> <height>  Sets the size of the chat window. Default is 225 by 150.
```
