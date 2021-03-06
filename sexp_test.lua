local testing = require('testing')
local sexp = require('sexp')
local assert = require('assert')

local function assert_eq(actual, expected, level)
   level = level or 2
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

local function test_read(input, expected_obj)
   local reader = sexp.Reader(input)
   local obj = reader:read()
   assert_eq(obj, expected_obj)
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
   test_read('1e3', {"int", 1000})
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
   test_read('0+', {"symbol", "0+"})
   test_read('-0-', {"symbol", "-0-"})
   test_read('0.0.0', {"symbol", "0.0.0"})
   test_read('-0.0.0', {"symbol", "-0.0.0"})
   test_read('5abc', {"symbol", "5abc"})
   test_read('-5abc', {"symbol", "-5abc"})
   test_read('123abc', {"symbol", "123abc"})
   test_read('-123abc', {"symbol", "-123abc"})
   test_read('63.25abc', {"symbol", "63.25abc"})
   test_read('-63.25abc', {"symbol", "-63.25abc"})
   test_read('0.5e3abc', {"symbol", "0.5e3abc"})
   test_read('-0.5e3abc', {"symbol", "-0.5e3abc"})
   test_read('1e3abc', {"symbol", "1e3abc"})
   test_read('-', {"symbol", "-"})
   test_read('-abc', {"symbol", "-abc"})
   test_read([[alpha beta gamma]], {"symbol", "alpha"})
   test_read(" 	\nbeta gamma", {"symbol", "beta"})
   test_read([[gamma123!@#$%^&*]], {"symbol", "gamma123!@#$%^&*"})
end)

testing('lists', function()
   test_read([[
(123 abc
  (+ 5 3) ; comment
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

testing("reader macros", function()
  local reader = sexp.Reader("(let form '(+ 2 3))")
  reader:register_macro("'", function(r)
     return {"list", {
                {"symbol", "quote"},
                r:read_form() }}
  end)
  local obj = reader:read()
  assert_eq(obj,
            {"list", {
                {"symbol", "let"},
                {"symbol", "form"},
                {"list", {
                    {"symbol", "quote"},
                    {"list", {
                        {"symbol", "+"},
                        {"int", 2},
                        {"int", 3}}}}}}})
end)

testing('custom lists', function()
  local reader = sexp.Reader [[
(let (x [0 1 (5 8) 2 #[9 7] 3 4]
      y #[a b c]
      z (phi beta)))
]]
  reader:register_macro('#[', function(r)
     return { "set", r:read_forms(']') }
  end)
  reader:register_macro('[', function(r)
     return { "vector", r:read_forms(']') }
  end)
  local obj = reader:read()
  assert_eq(obj,
            {"list", {
                {"symbol", "let"},
                {"list", {
                    {"symbol", "x"},
                    {"vector", {
                        {"int", 0},
                        {"int", 1},
                        {"list", {
                            {"int", 5},
                            {"int", 8}}},
                        {"int", 2},
                        {"set", {
                            {"int", 9},
                            {"int", 7}}},
                        {"int", 3},
                        {"int", 4}}},
                    {"symbol", "y"},
                    {"set", {
                        {"symbol", "a"},
                        {"symbol", "b"},
                        {"symbol", "c"}}},
                    {"symbol", "z"},
                    {"list", {
                        {"symbol", "phi"},
                        {"symbol", "beta"}}}}}}})
end)

testing('word parsers', function()
   local reader = sexp.Reader("(let form (+ 2 3))")
   reader:register_word("^f\\w+", function(m)
     return { "special", m[0] }
   end)
   local obj = reader:read()
   assert_eq(obj,
             {"list", {
                 {"symbol", "let"},
                 {"special", "form"},
                 {"list", {
                     {"symbol", "+"},
                     {"int", 2},
                     {"int", 3}}}}})
end)
