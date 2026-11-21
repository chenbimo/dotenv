///|
/// 加载 `.env` 时唯一会失败的两种情况。
///
/// `Unreadable` 是「文件存在但读不了」——权限、IO 错误。文件**不存在**不算错误，
/// 那是最常见的正常状态。
///
/// `Malformed` 只在严格入口出现：宽松入口按 Bun 的行为静默跳过坏行。带上文件名与
/// 行号，因为 `.env` 出错时最贵的问题就是「不知道是哪个文件的哪一行」。
pub suberror EnvError {
  Unreadable(String)
  Malformed(String, Int32, String)
}

///|
/// 人类可读的描述。带上路径与行号，直接用在对用户的报错里。
pub fn EnvError::describe(self : EnvError) -> String {
  match self {
    Unreadable(path) => "cannot read env file: " + path
    Malformed(path, line, reason) =>
      path + " line " + line.to_string() + ": " + reason
  }
}

///|
/// 内部用：把一行里的位置信息拼成完整错误。
fn malformed(path : String, line : Int32, reason : String) -> EnvError {
  Malformed(path, line, reason)
}
