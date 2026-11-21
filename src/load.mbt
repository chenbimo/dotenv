///|
/// 按 Bun 的顺序给出「会读哪些文件」：`.env` → `.env.<mode>` → `.env.local` →
/// `.env.<mode>.local`，后者覆盖前者；`mode = "test"` 时跳过 `.env.local`
/// （Bun 的既有行为）。
pub fn files(dir : String, mode : String) -> Array[String] {
  let names : Array[String] = if mode == "test" {
    [".env", ".env.test", ".env.test.local"]
  } else {
    [".env", ".env." + mode, ".env.local", ".env." + mode + ".local"]
  }
  let out : Array[String] = []
  for name in names {
    out.push(dir + "/" + name)
  }
  out
}

///|
/// 加载并合并一个目录下的 `.env` 文件。缺文件跳过、坏行跳过——与 Bun 的运行时
/// 行为一致。用于「读一份配置来跑程序」的场合。
///
/// `lookup` 是进程环境查询，由调用方注入：库本身不碰全局状态，测试时可以完全控制
/// 输入，调用方也能决定「进程环境」到底指谁的环境。
pub fn load(
  dir : String,
  mode : String,
  lookup : (String) -> String?,
) -> Map[String, String] raise EnvError {
  load_impl(dir, mode, lookup, strict=false)
}

///|
/// 与 `load` 相同，但把坏行当成错误抛出（带文件名与行号）。
///
/// 用于配置校验：运行时要的是「像 Bun 一样能跑」，校验要的是「坏行必须暴露」。
/// 两条入口共用同一份解析实现，不存在两套语义。
pub fn load_strict(
  dir : String,
  mode : String,
  lookup : (String) -> String?,
) -> Map[String, String] raise EnvError {
  load_impl(dir, mode, lookup, strict=true)
}

///|
/// 合并规则：逐个文件解析 → 各自在「进程环境 + 本文件」的作用域内展开 → 按顺序覆盖。
/// 最后按「进程环境优先」归一，保证同一个名字在应用与加载方读到同一个值。
fn load_impl(
  dir : String,
  mode : String,
  lookup : (String) -> String?,
  strict~ : Bool,
) -> Map[String, String] raise EnvError {
  let merged : Map[String, String] = Map([])
  for path in files(dir, mode) {
    if !@fs.path_exists(path) {
      continue
    }
    let text = try @fs.read_file_to_string(path) catch {
      _ => raise Unreadable(path)
    } noraise {
      content => content
    }
    let raw = parse_text(text, path, strict~)
    for pair in expand_map(raw, lookup).iter() {
      let (key, value) = pair
      match lookup(key) {
        Some(env_value) => merged[key] = env_value
        None => merged[key] = value
      }
    }
  }
  merged
}
