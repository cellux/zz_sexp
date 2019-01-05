local testing = require('testing')
local sexp = require('sexp')
local assert = require('assert')

local function test_read(input, expected_obj)
   local function assert_eq(actual, expected, level)
      local exp_kind, exp_value, exp_offset = unpack(expected)
      -- kind
      assert.type(exp_kind, "string")
      local act_kind = actual[1]
      assert.type(act_kind, "string")
      assert.equals(act_kind, exp_kind, "kind", level+1)
      -- value
      local act_value = actual[2]
      if act_kind == "list" then
         assert.type(act_value, "table")
         assert.type(exp_value, "table")
         if #act_value ~= #exp_value then
            pf("expected: %s", require('inspect')(exp_value))
            pf("actual: %s", require('inspect')(act_value))
         end
         assert.equals(#act_value, #exp_value)
         for i=1,#act_value do
            assert_eq(act_value[i], exp_value[i], level+1)
         end
      else
         assert.equals(act_value, exp_value, "value", level+1)
      end
      -- offset
      if exp_offset then
         local act_offset = actual[3]
         assert.type(act_offset, "number")
         assert.type(exp_offset, "number")
         assert.equals(act_offset, exp_offset, "offset", level+1)
      end
   end
   local reader = sexp.Reader(input)
   local obj = reader:read()
   assert_eq(obj, expected_obj, 2)
end

testing('numbers', function()
   test_read('0', {"int", 0})
   test_read('-0', {"int", 0})
   test_read('0.0', {"float", 0})
   test_read('-0.0', {"float", 0})
   test_read('5', {"int", 5})
   test_read('-5', {"int", -5})
   test_read('123', {"int", 123})
   test_read('-123', {"int", -123})
   test_read('63.25', {"float", 63.25})
   test_read('-63.25', {"float", -63.25})
   test_read('0.5e3', {"float", 500})
   test_read('-0.5e3', {"float", -500})
   test_read('1e3', {"float", 1000})
   test_read('-', {"symbol", "-"})
   test_read('-abc', {"symbol", "-abc"})
end)

testing('strings', function()
   test_read([["hello, world"]], {"string", "hello, world"})
   test_read([["hello, \"world\""]], {"string", "hello, \"world\""})
   test_read([["\a\b\f\n\r\t\v\\\"\'\
\x61zzz"]], {"string", "\a\b\f\n\r\t\v\\\"\\'\\\nazzz" })
   assert.throws('missing delimiter', function() test_read([["hello]]) end)
   assert.throws('missing delimiter', function() test_read([["hello\]]) end)
end)

testing('symbols', function()
   test_read([[alpha beta gamma]], {"symbol", "alpha"})
   test_read(" 	\nbeta gamma", {"symbol", "beta"})
   test_read([[gamma123!@#$%^&*]], {"symbol", "gamma123!@#$%^&*"})
end)

testing('lists', function()
   test_read([[
(123 abc
  (+ 5 3)
  "hello" 
)]],
      {"list", {
          {"int", 123},
          {"symbol", "abc"},
          {"list", {
              {"symbol", "+"},
              {"int", 5 },
              {"int", 3 }}},
          {"string", "hello"}}})
end)
