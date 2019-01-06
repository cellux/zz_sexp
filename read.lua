local fs = require('fs')
local sexp = require('sexp')
local inspect = require('inspect')

local M = {}

function M.main()
   local path = arg[1]
   if not path then
      pf("Usage: %s <path>", arg[0])
   elseif not fs.exists(path) then
      pf("File not found: %s", path)
   else
      local f = fs.open(path)
      local reader = sexp.Reader(f)
      local obj = reader:read()
      while obj do
         local repr = inspect(obj)
         print(repr)
         obj = reader:read()
      end
      f:close()
   end
end

return M
