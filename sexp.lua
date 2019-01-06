local util = require('util')
local stream = require('stream')
local buffer = require('buffer')
local re = require('re')

local M = {}

local regex = {
   ws = re.compile("^\\s+"),
   word = re.compile("^\\S+"),
   number = re.compile("^-?[0-9]+(\\.[0-9]+)?(e-?[0-9]+)?$"),
   comment = re.compile("^;.*?\\R"),
}

-- readers of default macros

local function read_list(r)
   return { "list", r:read_forms(')') }
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

local function read_string(r)
   local str = buffer.new()
   while not r:eof() do
      local ch = r:read_char()
      if ch == '\\' then
         ch = r:read_char()
         if ch then
            local replacement = string_escapes[ch]
            if replacement then
               str:append(replacement)
            elseif ch == 'x' then
               local m = r:pmatch("^[0-9a-fA-F]{2}")
               if m then
                  str:append(string.char(tonumber(m[0], 16)))
               else
                  str:append('\\x')
               end
            else
               str:append('\\'..ch)
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

-- parsers of default words

local function parse_number(m)
   if m[1] then
      return { "float", tonumber(m[0]) }
   else
      return { "int", tonumber(m[0]) }
   end
end

local function parse_symbol(m)
   return { "symbol", m[0] }
end

M.Reader = function(input)
   if not input then
      ef("missing input")
   end
   local input = stream(input)

   local self = {}

   function self:pmatch(pattern)
      local m = input:match(pattern)
      if m then
         self.last_match = m
         return m
      else
         return nil
      end
   end

   function self:match(prefix)
      if input:peek(#prefix) == prefix then
         input:read(#prefix)
         self.last_match = prefix
         return prefix
      else
         return nil
      end
   end

   function self:read_char()
      return input:read_char()
   end

   function self:eof()
      return input:eof()
   end

   local function skip_ws()
      input:match(regex["ws"])
   end

   -- macros

   local macros = {}

   function self:register_macro(prefix, read)
      table.insert(macros, { prefix, read })
   end

   self:register_macro('(', read_list)
   self:register_macro('"', read_string)

   -- words

   local words = {}

   function self:register_word(regex, parse)
      table.insert(words, { regex, parse })
   end

   self:register_word(regex["number"], parse_number)
   self:register_word(regex["word"], parse_symbol)

   --- main

   function self:read_forms(close_delim)
      local forms = {}
      while true do
         local form = self:read_form(close_delim)
         if not form then
            break
         else
            table.insert(forms, form)
         end
      end
      return forms
   end

   function self:read_form(close_delim)

      local function match_comment()
         return self:pmatch(regex["comment"])
      end

      local macro_read

      local function match_macro()
         macro_read = nil
         for _,v in ipairs(macros) do
            -- { prefix, read }
            if self:match(v[1]) then
               macro_read = v[2]
               break
            end
         end
         return macro_read
      end

      local word_parse

      local function match_word(word)
         word_parse = nil
         for _,v in ipairs(words) do
            -- { regex, parse }
            local m = v[1]:match(word)
            if m then
               self.last_match = m
               word_parse = v[2]
               break
            end
         end
         return word_parse
      end

      skip_ws()
      if close_delim and self:match(close_delim) then
         return nil -- reached the end of a list-like structure
      elseif match_comment() then
         -- match_comment() consumed the comment
         --
         -- to read the next form, we invoke read_form recursively
         return self:read_form(close_delim)
      elseif match_macro() then
         -- match_macro() sets `macro_read` to the right reader
         return macro_read(self)
      elseif self:pmatch(regex["word"]) then
         local word = self.last_match[0]
         -- strip closing delimiter (if any)
         if close_delim then
            local delim_index = word:find(close_delim, 1, true)
            if delim_index then
               input:unread(word:sub(delim_index))
               word = word:sub(1,delim_index-1)
            end
         end
         if match_word(word) then
            -- match_word() sets `word_parse` to the right parser
            return word_parse(self.last_match)
         end
      elseif close_delim then
         -- reached the end of input without finding close_delim
         ef("missing end delimiter: %s", close_delim)
      else
         -- reached the end of input
         return nil
      end
   end

   function self:read()
      return self:read_form()
   end

   return self
end

return M
