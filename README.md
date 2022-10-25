# TPTMPv2

A script for [The Powder Toy](https://powdertoy.co.uk/) which lets you and your
friends create landscapes and cities together... and then blow them up!

![a developer and his cousin blowing up id:121412](https://user-images.githubusercontent.com/3286587/132169104-f3a33166-a2f7-4a62-9613-cded7d6fbb9e.gif)

## Client usage

Ideally, you would install this script from the
[Script Manager](https://tpt.io/:19400). If for some reason that is not feasible
or desired, grab the file named `tptmp.lua` from the latest release on the
Releases page and add it to your autorun sequence. How you do this is up to you.

## Server usage

### Prerequisites

The server is meant to be run on _anything but Windows_ ([a limitation of
cqueues](http://25thandclement.com/~william/projects/cqueues.html)) using
[Lua 5.3](https://www.lua.org/versions.html#5.3) or above. It has a number of
dependencies, namely:

 * `lunajson`
 * `jnet`
 * `http`
 * `luafilesystem`
 * `basexx` (comes with `http`)
 * `cqueues` (comes with `http`)
 * `luaossl` (comes with `http`)

If you have [LuaRocks](https://luarocks.org/), you can install these with:

```sh
sudo luarocks install --lua-version=5.3 --tree=system lunajson
sudo luarocks install --lua-version=5.3 --tree=system jnet
sudo luarocks install --lua-version=5.3 --tree=system http
sudo luarocks install --lua-version=5.3 --tree=system luafilesystem
```

### Static configuration

Static configuration is the collection of settings that only ever change when
the server administrator changes them. This includes things such as which
interface to listen on, how many clients are allowed to connect at once, the
path to the dynamic configuration file, etc. All static configuration happens
in [tptmp/server/config.lua](tptmp/server/config.lua), see that file for further
details on configuration options. That file is under version control, but most
options in it can be offloaded to tptmp/server/secret_config.lua, which is not.

### Dynamic configuration

Dynamic configuration is the collection of settings that are not part of
static configuration. This includes things like room ownership,
block lists, MOTDs, etc. The dynamic configuration is a JSON file,
the path to which is specified by the static configuration options
`dynamic_config_main` and `dynamic_config_xchg` (the
latter being the path to the backup configuration in case the main one is
somehow corrupted while being modified). See
[tptmp/server/plugins](tptmp/server/plugins) for details on how plugins use
the dynamic configuration store.

### Running the server

The recommended way to run the server is via your service manager of choice. A
[systemd](https://systemd.io/) service template is provided for convenience in
the form of [tptmp.service.template](tptmp.service.template), which you will
have to customize for your specific environment. The server itself is
`server.lua`, running which is as simple as:

```sh
./server.lua
```

This will create the dynamic configuration store in the current directory and
start listening for player connections on the port specified by the static
configuration option `port`. Make sure to allow connections through your
firewall to this port (but not `rcon_port`, see below).

### Moderating the server

In addition to listening for player connections, the server also listens for
a remote console on the port specified by the static configuration option
`rcon_port`. Only one client may connect at once, and the server attempts no
authentication of a client that connects. **The remote console client is meant
to connect from `localhost`. Never let connections to this port through your
firewall.**

The remote console protocol is a simple one-JSON-per-LF-terminated-line protocol
over TCP. The client requests changes to be made in the server state by sending
request objects, to which the server responds by sending response objects when
done. The server may also send log objects. See
[tptmp/server/remote_console.lua](tptmp/server/remote_console.lua) and the
plugins in [tptmp/server/plugins](tptmp/server/plugins) for further details on
these objects.

## Server usage with Docker

```sh
docker build -t tptmp .
docker run \
	-p 1337:34403 \
	-v /path/to/secret_config.lua:/tptmp/tptmp/server/secret_config.lua:ro \
	-v /path/to/config/dir:/tptmp/config \
	-it tptmp
```

With `/path/to/secret_config.lua` looking something like this for testing purposes:

```lua
return {
	secure = false,
	host = "localhost:36779",
	dynamic_config_main = "/tptmp/config/config.json",
	dynamic_config_xchg = "/tptmp/config/config.json~",
}
```

To enable TLS, inject the relevant files and point secret_config.lua at them.
To enable authentication, make sure the `host` option reflects the host:port pair
under which your server is exposed to the world. See Dynamic configuration above.

## Things to do

- [ ] some sort of support for custom elements, maybe room-level element
      negotiation
- [ ] add APIs to TPT in order to get rid of a few hideous hacks on
      the TPTMP side
- [ ] smarter foul language filtering
- [ ] mouse selection in the chat window
- [ ] make initial syncs more resilient to problems such as the client chosen
      to send its simulation data disconnecting
