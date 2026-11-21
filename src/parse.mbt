///|
/// 解析一份 `.env` 文本，返回键值映射（值仍是原文，未展开）。
///
/// 规则以 Bun v1.4.5 为准：三种引号都剥壳、未加引号值里的 `#` 也按注释截断、
/// `export` 前缀受支持、重复键后者覆盖、引号内可跨行。CRLF 先归一成 LF。
///
/// `strict` 为假时按 Bun 的行为跳过坏行（运行时用）；为真时报错（配置校验用）。
pub fn parse_text(
  text : String,
  path : String,
  strict~ : Bool = true,
) -> Map[String, String] raise EnvError {
  let out : Map[String, String] = Map([])
  let body = text
    .replace_all(old="\r\n", new="\n")
    .replace_all(old="\r", new="\n")
  let n = body.length()
  let mut i = 0
  let mut line = 1
  while i < n {
    i = skip_blanks(body, i)
    if i >= n {
      break
    }
    let c = body[i]
    if c == '\n' {
      i += 1
      line += 1
      continue
    }
    if c == '#' {
      let (next, next_line) = skip_line(body, i, line)
      i = next
      line = next_line
      continue
    }
    if has_export_prefix(body, i) {
      i = skip_blanks(body, i + 6)
    }
    let key_start = i
    while i < n && is_key_char(body[i]) {
      i += 1
    }
    let key = body[key_start:i].to_owned()
    i = skip_blanks(body, i)
    if key.is_empty() || i >= n || body[i] != '=' {
      if strict {
        raise malformed(path, line, "expected KEY=VALUE")
      }
      let (next, next_line) = skip_line(body, i, line)
      i = next
      line = next_line
      continue
    }
    i = skip_blanks(body, i + 1)
    let (value, next, next_line) = if i < n &&
      (body[i] == '"' || body[i] == '\'' || body[i] == '`') {
      read_quoted(body, i, line, path, strict~)
    } else {
      read_bare(body, i, line)
    }
    out[key] = value
    i = next
    line = next_line
  }
  out
}

///|
/// 只跳空格与制表符；换行是行的边界，由主循环负责。
fn skip_blanks(text : String, from : Int32) -> Int32 {
  let n = text.length()
  let mut i = from
  while i < n && (text[i] == ' ' || text[i] == '\t') {
    i += 1
  }
  i
}

///|
/// 跳到行尾之后，并在跨过换行时把行号加一。
fn skip_line(text : String, from : Int32, line : Int32) -> (Int32, Int32) {
  let n = text.length()
  let mut i = from
  while i < n && text[i] != '\n' {
    i += 1
  }
  if i < n {
    (i + 1, line + 1)
  } else {
    (i, line)
  }
}

///|
/// `export` 前缀必须是一个完整的词：`exportFOO=1` 的键是 `exportFOO`。
fn has_export_prefix(text : String, at : Int32) -> Bool {
  if at + 6 >= text.length() {
    return false
  }
  if text[at:at + 6].to_owned() != "export" {
    return false
  }
  let after = text[at + 6]
  after == ' ' || after == '\t'
}

///|
/// 键名允许的字符。Bun 接受点、横线与数字开头（实测 `A.B` / `A-B` / `1X` 都能读到），
/// 这里保持一致；空键名由调用方拦下。
fn is_key_char(c : UInt16) -> Bool {
  let v = c.to_int()
  (v >= 65 && v <= 90) ||
  (v >= 97 && v <= 122) ||
  (v >= 48 && v <= 57) ||
  v == 95 ||
  v == 46 ||
  v == 45
}

///|
/// 读一个引号包裹的值。三种引号都剥壳，引号内允许换行。
///
/// 双引号内解释 `\n` `\t` `\r` `\\` `\"`；单引号与反引号内一律字面。
/// `\$` 任何引号里都原样保留，交给展开阶段处理成字面 `$`——两段各管一件事，
/// 否则「先反转义再展开」会把转义出来的 `$` 又当成变量。
fn read_quoted(
  text : String,
  from : Int32,
  line : Int32,
  path : String,
  strict~ : Bool,
) -> (String, Int32, Int32) raise EnvError {
  let n = text.length()
  let quote = text[from]
  let interpret_escapes = quote == '"'
  let buf = StringBuilder()
  let mut i = from + 1
  let mut run = i
  let mut current_line = line
  while i < n {
    let c = text[i]
    if c == quote {
      buf.write_string(text[run:i].to_owned())
      let (after, after_line) = finish_quoted(
        text,
        i + 1,
        current_line,
        path,
        strict~,
      )
      return (buf.to_string(), after, after_line)
    }
    if interpret_escapes && c == '\\' && i + 1 < n {
      let decoded : String? = match text[i + 1] {
        'n' => Some("\n")
        't' => Some("\t")
        'r' => Some("\r")
        '\\' => Some("\\")
        '"' => Some("\"")
        _ => None
      }
      match decoded {
        Some(decoded) => {
          buf.write_string(text[run:i].to_owned())
          buf.write_string(decoded)
          i += 2
          run = i
          continue
        }
        None => {
          i += 1
          continue
        }
      }
    }
    if c == '\n' {
      current_line += 1
    }
    i += 1
  }
  raise malformed(path, line, "unterminated quote opened here")
}

///|
/// 引号闭合之后：允许空白、允许一个行尾注释，除此之外就是多余内容。
fn finish_quoted(
  text : String,
  from : Int32,
  line : Int32,
  path : String,
  strict~ : Bool,
) -> (Int32, Int32) raise EnvError {
  let n = text.length()
  let i = skip_blanks(text, from)
  if i < n && text[i] == '#' {
    return skip_line(text, i, line)
  }
  if i < n && text[i] != '\n' {
    if strict {
      raise malformed(path, line, "unexpected text after a quoted value")
    }
    return skip_line(text, i, line)
  }
  skip_line(text, i, line)
}

///|
/// 读一个未加引号的值：切到行尾，遇到第一个 `#` 就截断（Bun 行为，`a#b` 得 `a`），
/// 两侧空白去掉。
fn read_bare(
  text : String,
  from : Int32,
  line : Int32,
) -> (String, Int32, Int32) {
  let n = text.length()
  let mut i = from
  while i < n && text[i] != '\n' && text[i] != '#' {
    i += 1
  }
  let raw = text[from:i].to_owned().trim().to_owned()
  let (next, next_line) = if i < n && text[i] == '#' {
    skip_line(text, i, line)
  } else {
    skip_line(text, i, line)
  }
  (raw, next, next_line)
}
