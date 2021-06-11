# TPTMPv2

## Client usage

Ideally, you would install this script from the
[Script Manager](https://tpt.io/:19400). If for some reason that is not feasible
or desired, grab the file named `tptmp.lua` from the latest release on the
Releases page and add it to your autorun sequence. How you do this is up to you.

## Server usage

### Prerequisites

The server is meant to be run using Lua 5.3 or above. It has a number of
dependencies, namely:

 * `lunajson`
 * `jnet`
 * `http`
 * `luafilesystem`
 * `basexx` (comes with `http`)
 * `cqueues` (comes with `http`)
 * `luaossl` (comes with `http`)

If you have [LuaRocks](https://luarocks.org/), installing these is as simple as:

```sh
sudo luarocks install --lua-version=5.3 lunajson
sudo luarocks install --lua-version=5.3 jnet
sudo luarocks install --lua-version=5.3 http
sudo luarocks install --lua-version=5.3 luafilesystem
```

### Static configuration

Static configuration is the collection of settings that only ever change when
you, the server administrator, changes them. All static configuration happens
in [tptmp/server/config.lua](tptmp/server/config.lua).

### Dynamic configuration

Dynamic configuration is all the configuration that is not static. 

_I was interrupted by a bug report when writing this so it is currently
incomplete_.
