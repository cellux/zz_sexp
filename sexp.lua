local util = require('util')
local stream = require('stream')
local buffer = require('buffer')
local re = require('re')

local M = {}

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
   if not input then
      ef("missing input")
   end
   local input = stream(input)

   local self = {}

   function self:pmatch(pattern)
      local m = input:match(pattern)
      self.last_match = m
      return m
   end

   function self:match(prefix)
      if input:peek(#prefix) == prefix then
         input:read(#prefix)
         return prefix
      else
         return nil
      end
   end

   function self:read_char()
      return input:read_char()
   end

   local function skip_ws()
      input:match(regex["ws"])
   end

   -- list kinds

   local list_kinds = {}

   function self:register_list(kind, open_delim, close_delim)
      table.insert(list_kinds, { kind, open_delim, close_delim })
   end

   self:register_list('list', '(', ')')

   -- string kinds

   local string_kinds = {}

   function self:register_string(kind, open_delim, read)
      table.insert(string_kinds, { kind, open_delim, read })
   end

   local function read_string(r)
      local ch = r:read_char()
      if ch == '\\' then
         ch = r:read_char()
         if ch then
            local replacement = string_escapes[ch]
            if replacement then
               return replacement
            elseif ch == 'x' then
               local m = r:pmatch("^[0-9a-fA-F]{2}")
               if m then
                  return string.char(tonumber(m[0], 16))
               else
                  return '\\x'
               end
            else
               return '\\'..ch
            end
         else
            return '\\'
         end
      elseif ch == '"' then
         return nil
      else
         return ch
      end
   end

   self:register_string('string', '"', read_string)

   -- word kinds

   local word_kinds = {}

   function self:register_word(regex, parse)
      table.insert(word_kinds, { regex, parse })
   end

   local function parse_number(m)
      if m[1] then
         return { "float", tonumber(m[0]) }
      else
         return { "int", tonumber(m[0]) }
      end
   end

   self:register_word(regex["number"], parse_number)

   local function parse_symbol(m)
      return { "symbol", m[0] }
   end

   self:register_word(regex["word"], parse_symbol)

   --- main

   -- predeclaration due to mutual recursion
   local read_list, read_list_item

   read_list = function(close_delim)
      local items = {}
      while true do
         local item = read_list_item(close_delim)
         if not item then
            break
         else
            table.insert(items, item)
         end
      end
      return items
   end

   read_list_item = function(close_delim)

      local list_kind, list_close_delim

      local function match_list()
         list_kind = nil
         for _,v in ipairs(list_kinds) do
            -- { kind, open_delim, close_delim }
            if self:match(v[2]) then
               list_kind = v[1]
               list_close_delim = v[3]
               break
            end
         end
         return list_kind
      end

      local string_kind, string_read

      local function match_string()
         string_kind = nil
         for _,v in ipairs(string_kinds) do
            -- { kind, open_delim, read }
            if self:match(v[2]) then
               string_kind = v[1]
               string_read = v[3]
               break
            end
         end
         return string_kind
      end

      local function match_comment()
         return self:pmatch(regex["comment"])
      end

      local word_match, word_parse
      
      local function match_word(word)
         word_match = nil
         for _,v in ipairs(word_kinds) do
            -- { regex, parse }
            local m = v[1]:match(word)
            if m then
               word_match = m
               word_parse = v[2]
               break
            end
         end
         return word_match
      end

      skip_ws()
      if close_delim and self:match(close_delim) then
         return nil
      elseif match_list() then
         return { list_kind, read_list(list_close_delim) }
      elseif match_string() then
         local str = buffer.new()
         while not input:eof() do
            local piece = string_read(self)
            if not piece then
               return { string_kind, tostring(str) }
            else
               str:append(piece)
            end
         end
         util.throw("read error", "missing delimiter at end of string")
      elseif match_comment() then
         return read_list_item(close_delim)
      elseif self:pmatch(regex["word"]) then
         local word = self.last_match[0]
         if close_delim then
            local delim_index = word:find(close_delim, 1, true)
            if delim_index then
               input:unread(word:sub(delim_index))
               word = word:sub(1,delim_index-1)
            end
         end
         if match_word(word) then
            return word_parse(word_match)
         end
      elseif close_delim then
         ef("missing end delimiter: %s", close_delim)
      else
         return nil
      end
   end

   function self:read()
      return read_list_item()
   end
   return self
end

return M
