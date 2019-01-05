local util = require('util')
local stream = require('stream')
local buffer = require('buffer')
local re = require('re')

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
   ws = re.compile("^\\s+"),
   word = re.compile("^\\S+"),
   number = re.compile("^-?[0-9]+(\\.[0-9]+)?(e-?[0-9]+)?$"),
   comment = re.compile("^;.*?\\R"),
}

M.Reader = function(input)
   local self = {}
   input = stream(input)

   local m
   local function pmatch(pattern)
      m = input:match(pattern)
      return m
   end

   local function match(prefix)
      if input:peek(#prefix) == prefix then
         input:read(#prefix)
         return true
      else
         return false
      end
   end

   local function skip_ws()
      input:match(regex["ws"])
   end

   local read_string
   local read_list
   local read_list_item

   read_string = function()
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
                  if pmatch("^[0-9a-fA-F]{2}") then
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
            return String(tostring(str))
         else
            str:append(ch)
         end
      end
      util.throw("read error", "missing delimiter at end of string")
   end

   read_list = function(kind, delimiter)
      local items = {}
      while true do
         local item = read_list_item(delimiter)
         if not item then
            break
         else
            table.insert(items, item)
         end
      end
      return { kind, items }
   end

   read_list_item = function(delimiter)
      skip_ws()
      if delimiter and match(delimiter) then
         return nil
      elseif match('"') then
         return read_string()
      elseif match('(') then
         return read_list("list", ")")
      elseif pmatch(regex["comment"]) then
         return read_list_item(delimiter)
      elseif pmatch(regex["word"]) then
         local word = m[0]
         if delimiter then
            local delim_index = word:find(delimiter, 1, true)
            if delim_index then
               input:unread(word:sub(delim_index))
               word = word:sub(1,delim_index-1)
            end
         end
         local m = regex["number"]:match(word)
         if m then
            if m[1] then
               return Float(tonumber(m[0]))
            else
               return Int(tonumber(m[0]))
            end
         else
            return Symbol(word)
         end
      elseif delimiter then
         ef("missing end delimiter: %s", delimiter)
      end
   end

   function self:read()
      return read_list_item()
   end

   return self
end

return M
