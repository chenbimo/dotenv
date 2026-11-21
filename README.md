# dotenv

MoonBit 的 `.env` 加载库，语义以 **Bun v1.4.5** 为准：文件发现顺序、解析规则、变量展开，逐条对齐实测行为。

不做「另一套 dotenv 方言」——dotenv 生态里有 dotenv / dotenv-expand / Bun / Node 几种互不相同的实现，混用会在开发与生产之间产生静默的取值差异。本库只负责一件事：**按 Bun 的规则，把一组 `.env` 文件读成一个 Map**。

## 安装

```bash
moon add chensuiyi/dotenv
```

## 用法

```moonbit
fn main {
  // dir：`.env` 文件所在目录；mode："development" / "production" / "test"
  // lookup：进程环境查询，由调用方提供；测试时可注入
  let vars = @dotenv.load("/srv/api", "production", fn(n) { @env.get_env_var(n) })
  let port = match vars.get("PORT") {
    Some(v) => v
    None => "3000"
  }
  println(port)
}
```

三个入口：

| 函数 | 用途 |
| --- | --- |
| `load(dir, mode, lookup)` | 按 Bun 语义加载并合并；缺文件跳过、坏行跳过 |
| `load_strict(dir, mode, lookup)` | 同上，但坏行报错并指出文件与行号（配置校验用） |
| `files(dir, mode)` | 只给出「会读哪些文件」，按读取顺序 |

## 语义

### 文件发现

按优先级递增的顺序读取，后读的覆盖先读的：

1. `.env`
2. `.env.<mode>`
3. `.env.local`（`mode = "test"` 时跳过，与 Bun 一致）
4. `.env.<mode>.local`

文件不存在视为正常；存在但读不了是硬错误。

### 语法

- `KEY=VALUE`，值两侧空白去掉；空值保留为空串
- 三种引号：`"..."`、`'...'`、`` `...` ``，都剥壳；引号内可跨行
- `#` 注释：整行，或值之后；**未加引号的值里出现 `#` 也按注释截断**（`a#b` → `a`）
- `export KEY=VALUE` 前缀受支持
- 重复键后者覆盖前者
- CRLF 行尾会被正确处理

### 变量展开

| 写法 | 结果 |
| --- | --- |
| `$NAME` / `${NAME}` | 取该名字的值 |
| `${NAME:-默认}` | 名字**未定义**时用默认值；名字存在但为空**不**触发 |
| `${NAME:-${OTHER}}` | 默认值本身也会展开 |
| `${未定义}` | 空串 |
| `\$NAME` | 字面 `$NAME`（引号内外一致） |
| 单引号内的 `$NAME` | **也会展开**（与 dotenv 不同，与 Bun 一致） |
| 自引用 / 循环引用 | 保留原字面，不展开 |
| 多层引用 | **只展开一层**，被引用的值不再递归 |

### 作用域

展开的作用域 = **进程环境（`lookup`）+ 本文件**，其中：

- 本文件内可前向引用（引用后面才定义的键）
- **不跨文件**：`.env.local` 里引用 `.env` 定义的键，展开结果是空串

同名变量在进程环境里已存在时，**进程环境优先**，文件不覆盖它。

## 明确不做

- 不写进程环境（纯函数，只返回 Map）——写入由调用方决定
- 不做 `NODE_ENV` 一致性校验——那是上层工具的职责
- 不支持 `\\`（双反斜杠）转义。Bun 对 `\\${A}` 的结果既不是「转义成一个 `\`」也不是「保留原文」，是个无法自洽的边缘行为；请勿在值里使用 `\\`
- 不提供 `dotenv` 风格的 `config()`（自动写入 `process.env`）

## 测试

```bash
moon test --target native
```

语义即契约：`AGENTS.md` 里的规则表与 `src/*_test.mbt` 的用例一一对应。
