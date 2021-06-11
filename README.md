# TPTMPv2

A script for [The Powder Toy](https://powdertoy.co.uk/) which lets you and your
friends create landscapes and cities together... and then blow them up!

## Client usage

Ideally, you would install this script from the
[Script Manager](https://tpt.io/:19400). If for some reason that is not feasible
or desired, grab the file named `tptmp.lua` from the latest release on the
Releases page and add it to your autorun sequence. How you do this is up to you.

## Server usage

### Prerequisites

The server is meant to be run using
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
sudo luarocks install --lua-version=5.3 lunajson
sudo luarocks install --lua-version=5.3 jnet
sudo luarocks install --lua-version=5.3 http
sudo luarocks install --lua-version=5.3 luafilesystem
```

### Static configuration

Static configuration is the collection of settings that only ever change when
you, the server administrator, changes them. This includes things such as which
interface to listen on, how many clients are allowed to connect at once, the
path to the dynamic configuration file, etc. All static configuration happens
in [tptmp/server/config.lua](tptmp/server/config.lua), see that file for further
details on configuration options.

### Dynamic configuration

Dynamic configuration is all the configuration that is not static. This is
includes things like room ownership, 

_I was interrupted by a bug report when writing this so it is currently
incomplete_.

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

## Things to do

- [ ] more administration facilities, such as room ownership management, via the
      remote console
- [ ] some sort of support for custom elements
