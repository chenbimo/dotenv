///|
/// 测试用：把若干键值对装成 Map。
fn raw_map(pairs : Array[(String, String)]) -> Map[String, String] {
  let m : Map[String, String] = Map([])
  for pair in pairs {
    let (key, value) = pair
    m[key] = value
  }
  m
}

///|
/// 测试用：进程环境里只有一个变量。
fn env_with(name : String, value : String) -> (String) -> String? {
  fn(key) { if key == name { Some(value) } else { None } }
}

///|
test "both $NAME and ${NAME} expand" {
  let raw = raw_map([("P", "plain"), ("A", "${P}-x"), ("B", "$P-y")])
  let out = @dotenv.expand_map(raw, no_env)
  assert_eq(out.get("A"), Some("plain-x"))
  assert_eq(out.get("B"), Some("plain-y"))
}

///|
test "an undefined reference becomes the empty string" {
  let raw = raw_map([("A", "[${NOPE}]")])
  assert_eq(@dotenv.expand_map(raw, no_env).get("A"), Some("[]"))
}

///|
test "a default applies only when the name is undefined" {
  let raw = raw_map([("A", "${NOPE:-fb}"), ("B", "${EMPTY:-fb}"), ("EMPTY", "")])
  let out = @dotenv.expand_map(raw, no_env)
  assert_eq(out.get("A"), Some("fb"))
  assert_eq(out.get("B"), Some(""))
}

///|
test "the default itself may reference another name" {
  let raw = raw_map([("P", "plain"), ("A", "${NOPE:-${P}}-x")])
  assert_eq(@dotenv.expand_map(raw, no_env).get("A"), Some("plain-x"))
}

///|
test "a backslash-dollar is a literal dollar sign" {
  let raw = raw_map([("P", "plain"), ("A", "\\${P}"), ("B", "\\$P")])
  let out = @dotenv.expand_map(raw, no_env)
  assert_eq(out.get("A"), Some("${P}"))
  assert_eq(out.get("B"), Some("$P"))
}

///|
test "forward references resolve inside one file" {
  let raw = raw_map([("A", "${LATER}"), ("LATER", "late")])
  assert_eq(@dotenv.expand_map(raw, no_env).get("A"), Some("late"))
}

///|
test "expansion is single layer, not recursive" {
  let raw = raw_map([("A", "${B}"), ("B", "${C}"), ("C", "deep")])
  let out = @dotenv.expand_map(raw, no_env)
  assert_eq(out.get("A"), Some("${C}"))
  assert_eq(out.get("B"), Some("deep"))
}

///|
test "self reference keeps the literal text" {
  let raw = raw_map([("S", "${S}")])
  assert_eq(@dotenv.expand_map(raw, no_env).get("S"), Some("${S}"))
}

///|
test "a cycle terminates and keeps a literal" {
  let raw = raw_map([("X", "${Y}"), ("Y", "${X}")])
  let out = @dotenv.expand_map(raw, no_env)
  assert_eq(out.get("X"), Some("${X}"))
  assert_eq(out.get("Y"), Some("${Y}"))
}

///|
/// 展开只管「引用到哪里取」，不管「最终谁覆盖谁」——后者是 load 的合并职责，
/// 见 load_test 里的同名用例。
test "references resolve to the process environment first" {
  let raw = raw_map([("A", "from-file"), ("B", "${A}")])
  let out = @dotenv.expand_map(raw, env_with("A", "from-env"))
  assert_eq(out.get("A"), Some("from-file"))
  assert_eq(out.get("B"), Some("from-env"))
}

///|
test "a lone dollar stays as text" {
  let raw = raw_map([("A", "100$"), ("B", "$ x")])
  let out = @dotenv.expand_map(raw, no_env)
  assert_eq(out.get("A"), Some("100$"))
  assert_eq(out.get("B"), Some("$ x"))
}

///|
test "expansion covers what parsing produced for an escaped literal" {
  // 文本经 parse 后 `\$` 仍是两个字符，展开阶段才变成字面 `$`
  let m = @dotenv.parse_text("P=plain\nA=\\${P}\n", "/t/.env")
  assert_eq(@dotenv.expand_map(m, no_env).get("A"), Some("${P}"))
}
