local util = require('util')
local stream = require('stream')
local buffer = require('buffer')
local re = require('re')
local adt = require('adt')

local M = {}

local function Int(value)
   return { "int", value }
end

local function Float(value)
   return { "float", value }
end

local function String(value)
   return { "string", value }
end

local function Symbol(name)
   return { "symbol", name }
end

local string_escapes = {
   a = "\a",
   b = "\b",
   f = "\f",
   n = "\n",
   r = "\r",
   t = "\t",
   v = "\v",
   ["\""] = "\"",
   ["\\"] = "\\",
}

local regex = {
   int = re.compile("^-?[0-9]+"),
   float_suffix = re.compile("^(\\.[0-9]+)?(e-?[0-9]+)?"),
   symbol = re.compile("^[^\\s)]+"),
   comment = re.compile("^;.*?\\R"),
}

M.Reader = function(input)
   local self = {}
   input = stream(input)

   local function read_string()
      local str = buffer.new()
      while not input:eof() do
         local ch = input:read_char()
         if ch == '\\' then
            ch = input:read_char()
            if ch then
               local replacement = string_escapes[ch]
               if replacement then
                  str:append(replacement)
               elseif ch == 'x' then
                  local m = input:match("^[0-9a-fA-F]{2}")
                  if m then
                     str:append(string.char(tonumber(m[0], 16)))
                  else
                     str:append('\\x')
                  end
               elseif ch then
                  str:append('\\')
                  str:append(ch)
               end
            else
               str:append('\\')
            end
         elseif ch == '"' then
            return { "string", tostring(str) }
         else
            str:append(ch)
         end
      end
      util.throw("read error", "missing delimiter at end of string")
   end

   local function skip_ws()
      input:match("^\\s+")
   end

   local function match(prefix)
      if input:peek(#prefix) == prefix then
         input:read(#prefix)
         return true
      else
         return false
      end
   end

   local function read_list()
      local items = {}
      while true do
         skip_ws()
         if match(')') then
            break
         end
         local item = self:read()
         if not item then
            ef("missing end delimiter: %s", ')')
         else
            table.insert(items, item)
         end
      end
      return { "list", items }
   end

   function self:read()
      skip_ws()
      local m
      local function pmatch(pattern)
         m = input:match(pattern)
         return m
      end
      if pmatch(regex["int"]) then
         local num = m[0]
         if pmatch(regex["float_suffix"]) then
            num = num .. m[0]
            return Float(tonumber(num))
         else
            return Int(tonumber(num))
         end
      elseif match('"') then
         return read_string()
      elseif match('(') then
         return read_list()
      elseif pmatch(regex["comment"]) then
         return self:read()
      elseif pmatch(regex["symbol"]) then
         return Symbol(m[0])
      end
   end

   return self
end

return M
