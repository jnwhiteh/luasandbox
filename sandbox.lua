-- This script accepts a single argument, being the filename of a script
-- to be run.  It expects to be executed under the ulimit command of the
-- bash shell.  It provides a very simple sandbox that doesn't have any
-- persistent state.  This is intentional.

local modules = {
	"bit",
	"lpeg",
	"md5",
}

pcall(require, "luarocks.require")

for idx,mod in ipairs(modules) do
	local succ, err = pcall(require, mod)
end

-- Grab the filename from the genv, so we have it available
local filename = arg[1]
local pluto_filename = arg[2]

-- Save what we need to have access to in order to run
local genv = getfenv(0)
local io = genv.io
local os = genv.os
local string = genv.string 
local table = genv.table
local type = genv.type
local print = genv.print
local floor = genv.math.floor
local loadstring = genv.loadstring
local getmetatable = genv.getmetatable
local setmetatable = genv.setmetatable
local pcall = genv.pcall
local tostring = genv.tostring
local pairs = genv.pairs
local error = genv.error
local pluto = select(2, pcall(require, "pluto"))
local open = io.open
local select = genv.select
local getinfo = genv.debug.getinfo

-- Make a copy of the true global environment
local penv = {}
for k,v in pairs(genv) do penv[k] = v end
setmetatable(penv, getmetatable(genv))

-- Clear the true global environment so we can build it from scratch
for k,v in pairs(genv) do genv[k] = nil end
setmetatable(genv, {__metatable={}})

-- This function allows you to expose global variables, as well as namespace functions
-- i.e. it accepts keys such as "tostring", as well as "string.format".

local function expose(tbl)
	for idx,key in pairs(tbl) do
		if type(key) ~= "string" then
			error("Attempt to expose a non-string key: " .. tostring(key))
		end

		-- If the key matches directly then copy it
		if penv[key] then
			genv[key] = penv[key]
			-- TODO: Error if the key isn't there
		else
			local namespace,subkey = key:match("^([^%.]+)%.(.+)$")
			local nsTbl = penv[namespace]
			if type(nsTbl) == "table" and type(nsTbl[subkey]) ~= "nil" then
				genv[namespace] = genv[namespace] or {}
				genv[namespace][subkey] = penv[namespace][subkey]
			else
				error("Attempt to expose a non-existant namespace value: " .. tostring(key))
			end
		end
	end
end

expose{
	"assert",			
	"collectgarbage",		-- Should be safe in our throwaway environment, due to ulimit
	"error",
	"_G",					-- No reason this can't be exposed
    "gcinfo",
	"getfenv",				-- We should be fine with this, since they can't outside of it
	"getmetatable",
	"ipairs",
	"load",
	"loadstring",
	"next",
	"pairs",
	"pcall",
	"print",				-- Expose this as a backup, but we redefine it below
	"rawequal",
	"rawget",
	"rawset",
	"select",
	"setfenv",
	"setmetatable",
	"tonumber",
	"tostring",				-- This is REQUIRED for print to work properly
	"type",
	"unpack",
	"_VERSION",
	"xpcall",
	"os.clock",
	"os.date",
	"os.difftime",
	"os.time",
	"os.setlocale",
	"newproxy",				-- Until Shirik finds a way to break it
}

-- Export the strings,math and table libraries
local libs = {}
for k,v in pairs(penv.string) do table.insert(libs, "string."..k) end
for k,v in pairs(penv.math) do table.insert(libs, "math."..k) end
for k,v in pairs(penv.table) do table.insert(libs, "table."..k) end
for k,v in pairs(penv.coroutine) do table.insert(libs, "coroutine."..k) end
for idx,mod in ipairs(modules) do
	if penv[mod] then
		for k,v in pairs(penv[mod]) do table.insert(libs, mod .. "." .. k) end
	end
end

expose(libs)

-- Add the following lua-space split/join/concat/trim functions

local function quotemeta(i)
		return string.gsub(i, "[%%%[%]%*%.%-%?%$%^%(%)]", "%%%1")
end

local function __strsplit(re, str, lim)
	if (lim and lim <= 1) then return str end
	local pre, post = string.match(str, re)
	if (not pre) then
		return str
	end
	if (lim == 2) then
		return pre, post
	end
	return pre, __strsplit(re, post, lim and (lim - 1))
end

function genv.strsplit(del, str, lim)
	if (lim and lim <= 1) then return str end
	return __strsplit("^(.-)[" .. quotemeta(del) .. "](.*)$", str, lim)
end

function genv.strconcat(...)
	return table.concat({...})
end

function genv.strjoin(sep, ...)
	local l = select("#", ...)
	if (l == 0) then
		return
	elseif (l == 1) then
		return (...)
	end

	local t = {(...)}
	for i=2,l do
		table.insert(t, sep)
		table.insert(t, (select(i, ...)))
	end
	return table.concat(t)
end

function genv.strtrim(str)
		return str:match("%s*(.*)%s*")
end

genv.string.concat = genv.strconcat
genv.string.join = genv.strjoin
genv.string.split = genv.strsplit
genv.string.trim = genv.strtrim

-- Pretty print function

do
	local create_table_output
	local get_value
	local get_result

-- Serializes a table into a string
-- Code by: Cide of CTMod
local get_value; -- Needs to be accessed by create_table_output
local tbl_cache, tbl_num = { }, 0;
function create_table_output(tbl, no_cache)
	if ( tbl_cache[tbl] and not no_cache ) then
		return "<table: "..tbl_cache[tbl]..">";
	end

	local address = tbl_cache[tbl];
	if ( not address ) then
		tbl_num = tbl_num + 1;
		address = "#"..tbl_num;
		tbl_cache[tbl] = address;
	end

	local msg = "{ ";
	local num_ipairs = 0;
	for key, value in ipairs(tbl) do
		num_ipairs = key;
		msg = msg .. get_value(value) .. ", ";
	end
	for key, value in pairs(tbl) do
		if ( not tonumber(key) or math.floor(key) ~= key or ( key < 1 or key > num_ipairs ) ) then
			msg = msg .. "["..get_value(key).."] = " .. get_value(value) .. ", ";
		end
	end
	if ( string.match(msg, ", $") ) then
		msg = string.sub(msg, 1, -3);
	end
	msg = msg .. " } ("..address..")";
	return msg;
end

function get_result(...)
	local t = { ... };
	t.num = select('#', ...) - 1;
	return t;
end

-- Takes care of "serializing" a value
function get_value(value, no_cache)
	local vt = type(value);
	if ( vt == "string" ) then
		return "\""..value:gsub("\\", "\\\\"):gsub("\"", "\\\"").."\"";
	elseif ( vt == "table" ) then
		return create_table_output(value, no_cache);
    elseif ( vt == "function" ) then
        local info = getinfo(value, "n")
        if info and info.name then
            return string.format("function: '%s'", info.name)
        else
            return tostring(value)
        end
	else
		return tostring(value);
	end
end

	genv.prettyprint = function(...)
		for i=1,select("#", ...) do
			genv.print(get_value(select(i, ...)))
		end
	end

	genv.pp = genv.prettyprint

end

-- Custom private print function, will ensure the given 
-- prefix is printed before any other output
local prefixSent = false
local function output(prefix, text)
	if not prefixSent then
		io.stdout:write(prefix .. ":")
		prefixSent = true
	end

	if text then
		io.stdout:write(text)
	end
end

-- Add the custom print function
local addComma = false
function genv.print(...)
	local max = select("#", ...)
	for i=1,max do
		if addComma then
			io.stdout:write(", ")
		else
			addComma = true
		end

		local item = select(i, ...)
		output("OUT", tostring(tostring(item)))
	end
end

-- Let's properly sandbox the string metatable
getmetatable("").__metatable = {}

local file = io.open(filename, "r")
if type(file) ~= "userdata" then
	output("ERR", "Unexpected error running sandboxed code: file error")
	os.exit(1)
end

local script,err = file:read("*all")
if type(err) ~= "nil" then
		output("ERR", "Unexpected error running sandbox code: read error")
		os.exit(1)
end

-- If the first non-whitespace token in an =, convert it to print

if script:match("^%s*(%S)") == "=" then
	script = script:gsub("^%s*(%S)", "return ")
end

local func,err = loadstring(script, "=luabot")
local retfunc,reterr = loadstring("return " .. script, "=luabot")

-- Load any persistent state that has been sent to us
if pluto_filename and pluto_filename:match("%S") then
	local file = open(pluto_filename, "r")
	if file then
		local env = select(2, pcall(pluto.unpersist, {}, file:read("*all")))
		if type(env) == "table" then
			for k,v in pairs(env) do
				genv[k] = v
			end
		end
		file:close()
	end
end

-- A whole bit of nastiness to signal the output of the script as either error
-- or actual result, and to attempt to 'print' the results of a script that
-- might not otherwise have a result
if type(retfunc) ~= "function" then
	if type(func) ~= "function" then
		-- We officially have nothing to run, bail out with the first error
		output("ERR", err)
		os.exit(1)
	else
		-- Run this script, and hope it prints something
		output("OUT")
		genv.print(select(2, pcall(func)))
	end
else
	output("OUT")
	genv.print(select(2, pcall(retfunc)))
	
end
