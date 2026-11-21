///|
/// 测试用：无进程环境。
fn no_env(_name : String) -> String? {
  None
}

///|
test "bare value trims the edges and keeps inner spaces" {
  let m = @dotenv.parse_text("A=  spaced value  \n", "/t/.env")
  assert_eq(m.get("A"), Some("spaced value"))
}

///|
test "empty value stays an empty string" {
  let m = @dotenv.parse_text("A=\n", "/t/.env")
  assert_eq(m.get("A"), Some(""))
}

///|
test "whole line comment is skipped" {
  let m = @dotenv.parse_text("# note\nA=1\n", "/t/.env")
  assert_eq(m.get("A"), Some("1"))
  assert_eq(m.length(), 1)
}

///|
test "trailing comment after a bare value is dropped" {
  let m = @dotenv.parse_text("A=1 # note\n", "/t/.env")
  assert_eq(m.get("A"), Some("1"))
}

///|
test "hash inside an unquoted value truncates it, like Bun" {
  let m = @dotenv.parse_text("A=a#b\n", "/t/.env")
  assert_eq(m.get("A"), Some("a"))
}

///|
test "hash inside quotes survives" {
  let m = @dotenv.parse_text("A=\"a # b\"\n", "/t/.env")
  assert_eq(m.get("A"), Some("a # b"))
}

///|
test "all three quote styles are stripped" {
  let m = @dotenv.parse_text("A=\"x\"\nB='y'\nC=`z`\n", "/t/.env")
  assert_eq(m.get("A"), Some("x"))
  assert_eq(m.get("B"), Some("y"))
  assert_eq(m.get("C"), Some("z"))
}

///|
test "single quotes keep the backslash-n literal" {
  let m = @dotenv.parse_text("A='a\\nb'\n", "/t/.env")
  assert_eq(m.get("A"), Some("a\\nb"))
}

///|
test "double quotes turn backslash-n into a newline" {
  let m = @dotenv.parse_text("A=\"a\\nb\"\n", "/t/.env")
  assert_eq(m.get("A"), Some("a\nb"))
}

///|
test "export prefix is supported" {
  let m = @dotenv.parse_text("export A=1\n", "/t/.env")
  assert_eq(m.get("A"), Some("1"))
}

///|
test "a word starting with export is not a prefix" {
  let m = @dotenv.parse_text("exportFOO=1\n", "/t/.env")
  assert_eq(m.get("exportFOO"), Some("1"))
}

///|
test "later duplicate wins" {
  let m = @dotenv.parse_text("A=first\nA=second\n", "/t/.env")
  assert_eq(m.get("A"), Some("second"))
}

///|
test "quoted values may span lines" {
  let m = @dotenv.parse_text("A=\"line1\nline2\"\nB=2\n", "/t/.env")
  assert_eq(m.get("A"), Some("line1\nline2"))
  assert_eq(m.get("B"), Some("2"))
}

///|
test "CRLF line endings are handled" {
  let m = @dotenv.parse_text("A=1\r\nB=2\r\n", "/t/.env")
  assert_eq(m.get("A"), Some("1"))
  assert_eq(m.get("B"), Some("2"))
}

///|
test "key names may carry dots, dashes and leading digits" {
  let m = @dotenv.parse_text("A.B=1\nA-B=2\n1X=3\n", "/t/.env")
  assert_eq(m.get("A.B"), Some("1"))
  assert_eq(m.get("A-B"), Some("2"))
  assert_eq(m.get("1X"), Some("3"))
}

///|
test "lenient mode skips a line without an equals sign" {
  let m = @dotenv.parse_text("JUSTAKEY\nA=1\n", "/t/.env", strict=false)
  assert_eq(m.get("A"), Some("1"))
  assert_eq(m.length(), 1)
}

///|
test "strict mode reports a bad line with its number" {
  let outcome = try {
    ignore(@dotenv.parse_text("A=1\nJUSTAKEY\n", "/t/.env"))
    "no error"
  } catch {
    e => e.describe()
  }
  assert_true(outcome.contains("line 2"))
  assert_true(outcome.contains("/t/.env"))
}

///|
test "strict mode rejects text after a quoted value" {
  let outcome = try {
    ignore(@dotenv.parse_text("A=\"x\" garbage\n", "/t/.env"))
    "no error"
  } catch {
    e => e.describe()
  }
  assert_true(outcome.contains("unexpected text"))
}
