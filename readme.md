# Sandbox for running Lua code

This is a fairly simply sandbox for running user-supplied Lua code in what we
hope is a 'safe' way. This script does not attempt to do any memory or CPU limiting, as it expects to be run under the 'ulimit' command in order to accomplish this. This sandbox supports basic persistence using Pluto and allows you to easily customize the functions that are exposed to the user scripts.

# License

This code is made available under the same Licence as [Lua 5.0 and later versions][1]

[1]: http://www.lua.org/license.html