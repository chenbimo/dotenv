///|
/// 按 Bun 的规则展开一份已解析的键值映射。
///
/// 作用域是「`lookup`（进程环境）+ 本文件」，不跨文件；只展开一层，被引用的值不再
/// 递归展开；未定义展开成空串；`${NAME:-默认}` 只在名字**未定义**时用默认值。
///
/// 自引用与循环引用天然得到 Bun 的结果：`A=${A}` 引用到自己时取到的原文就是
/// `${A}`，原样写回，不需要额外的环检测。
pub fn expand_map(
  raw : Map[String, String],
  lookup : (String) -> String?,
) -> Map[String, String] {
  let out : Map[String, String] = Map([])
  for pair in raw.iter() {
    let (key, value) = pair
    out[key] = expand_value(value, raw, lookup)
  }
  out
}

///|
/// 展开一个值。`\$` 转成字面 `$` 并就此打住，后面的字符不再参与引用解析。
fn expand_value(
  text : String,
  raw : Map[String, String],
  lookup : (String) -> String?,
) -> String {
  let n = text.length()
  let buf = StringBuilder()
  let mut i = 0
  let mut run = 0
  while i < n {
    let c = text[i]
    if c == '\\' && i + 1 < n && text[i + 1] == '$' {
      buf.write_string(text[run:i].to_owned())
      buf.write_string("$")
      i += 2
      run = i
      continue
    }
    if c == '$' {
      match read_ref(text, i) {
        Some((name, default, end)) => {
          buf.write_string(text[run:i].to_owned())
          match resolve(name, raw, lookup) {
            Some(value) => buf.write_string(value)
            None =>
              match default {
                Some(fallback) =>
                  buf.write_string(expand_value(fallback, raw, lookup))
                None => ()
              }
          }
          i = end
          run = i
          continue
        }
        // 不是合法引用：`$` 当普通字符，留在片段里一起输出。
        None => {
          i += 1
          continue
        }
      }
    }
    i += 1
  }
  buf.write_string(text[run:n].to_owned())
  buf.to_string()
}

///|
/// 在指向 `$` 的位置解析一个引用，返回（名字, 默认值, 结束下标）。
/// `None` 表示这个 `$` 后面不是引用，按普通字符处理。
fn read_ref(text : String, at : Int32) -> (String, String?, Int32)? {
  let n = text.length()
  let i = at + 1
  if i < n && text[i] == '{' {
    let start = i + 1
    let mut j = start
    // 允许默认值里再嵌一层引用：`${A:-${B}}` 要找到外层那个 `}`。
    let mut depth = 0
    while j < n {
      let cj = text[j]
      if cj == '{' {
        depth += 1
      } else if cj == '}' {
        if depth == 0 {
          break
        }
        depth -= 1
      }
      j += 1
    }
    if j >= n {
      return None
    }
    let inner = text[start:j].to_owned()
    let end = j + 1
    match split_default(inner) {
      Some((name, fallback)) => Some((name, Some(fallback), end))
      None => Some((inner, None, end))
    }
  } else {
    let mut j = i
    while j < n && is_name_char(text[j]) {
      j += 1
    }
    if j == i {
      return None
    }
    Some((text[i:j].to_owned(), None, j))
  }
}

///|
/// `${NAME:-默认}` 的切分。只有 `:-` 受支持；`-`、`?` 之类保持原样（Bun 也不支持）。
fn split_default(inner : String) -> (String, String)? {
  let n = inner.length()
  let mut i = 0
  while i + 1 < n {
    if inner[i] == ':' && inner[i + 1] == '-' {
      return Some((inner[0:i].to_owned(), inner[i + 2:n].to_owned()))
    }
    i += 1
  }
  None
}

///|
/// 名字的解析顺序：进程环境优先，其次本文件。文件名里没有的返回 `None`。
fn resolve(
  name : String,
  raw : Map[String, String],
  lookup : (String) -> String?,
) -> String? {
  match lookup(name) {
    Some(value) => Some(value)
    None => raw.get(name)
  }
}

///|
/// 变量名允许的字符，与解析阶段保持同一套。
fn is_name_char(c : UInt16) -> Bool {
  let v = c.to_int()
  (v >= 65 && v <= 90) ||
  (v >= 97 && v <= 122) ||
  (v >= 48 && v <= 57) ||
  v == 95
}
