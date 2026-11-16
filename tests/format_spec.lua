local format = require("openbao.format")

describe("format.dotenv", function()
  it("round-trips plain, quoted and multi-line values", function()
    local data = {
      PLAIN = "abc123",
      EMPTY = "",
      SPACED = " a b ",
      QUOTE = 'say "hi"',
      MULTI = "line1\nline2",
      HASH = "a # b",
      URL = "postgres://u:p@host:5432/db?x=1",
    }
    local parsed = assert(format.parse_dotenv(format.dotenv_lines(data)))
    assert.are.same(data, parsed)
  end)

  it("ignores comments and blank lines, accepts `export`", function()
    local parsed = format.parse_dotenv({ "# comment", "", "export A=1", "B = two", "C='raw \\n'" })
    assert.are.same({ A = "1", B = "two", C = "raw \\n" }, parsed)
  end)

  it("reports errors with line numbers", function()
    local data, errs = format.parse_dotenv({ "A=1", "oops", "A=2", 'B="open' })
    assert.is_nil(data)
    assert.are.same({ "line 2: expected KEY=value", "line 3: duplicate key 'A'", "line 4: unterminated quote" }, errs)
  end)

  it("rejects a value ending with an escaped quote", function()
    local data = format.parse_dotenv({ 'A="x\\"' })
    assert.is_nil(data)
  end)
end)

describe("format.classify", function()
  it("uses dotenv for flat string secrets", function()
    assert.are.equal("dotenv", format.classify({ A = "1", ["db.pass"] = "x" }))
  end)

  it("falls back to json for non-string values or odd keys", function()
    assert.are.equal("json", format.classify({ A = 1 }))
    assert.are.equal("json", format.classify({ A = { b = "c" } }))
    assert.are.equal("json", format.classify({ ["a b"] = "x" }))
  end)
end)

describe("format.json", function()
  it("round-trips nested data with sorted keys", function()
    local data = { b = { c = { 1, 2 } }, a = true, n = 3, s = "x" }
    local lines = format.json_lines(data)
    assert.are.equal("{", lines[1])
    assert.are.equal('  "a": true,', lines[2])
    assert.are.same(data, format.parse_json(lines))
  end)

  it("rejects non-object top levels and invalid JSON", function()
    assert.is_nil(format.parse_json({ "[1,2]" }))
    local data, errs = format.parse_json({ "{" })
    assert.is_nil(data)
    assert.are.equal(1, #errs)
  end)
end)

describe("format.diff", function()
  it("lists added, changed and removed keys", function()
    local d = format.diff({ A = "1", B = "2", C = "3" }, { A = "1", B = "x", D = "4" })
    assert.are.same({ added = { "D" }, changed = { "B" }, removed = { "C" } }, d)
    assert.are.equal("+D ~B -C", format.describe(d))
    assert.is_false(format.is_empty(d))
    assert.is_true(format.is_empty(format.diff({ A = "1" }, { A = "1" })))
  end)
end)
