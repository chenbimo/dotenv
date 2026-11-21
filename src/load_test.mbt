///|
/// 测试用：在 `dir` 下写入给定的文件（先建目录，已存在则忽略）。
fn setup(dir : String, files : Array[(String, String)]) -> Unit raise {
  let _ = try @fs.create_dir(dir) catch {
    _ => ()
  } noraise {
    _ => ()
  }
  for pair in files {
    let (name, content) = pair
    @fs.write_string_to_file(dir + "/" + name, content)
  }
}

///|
/// 测试用：删掉 setup 写过的文件与目录，忽略所有清理错误。
fn teardown(dir : String, files : Array[(String, String)]) -> Unit {
  for pair in files {
    let (name, _) = pair
    let _ = try @fs.remove_file(dir + "/" + name) catch {
      _ => ()
    } noraise {
      _ => ()
    }
  }
  let _ = try @fs.remove_dir(dir) catch {
    _ => ()
  } noraise {
    _ => ()
  }
}

///|
test "files lists the four names in order" {
  let listed = @dotenv.files("/srv/api", "production")
  assert_eq(listed[0], "/srv/api/.env")
  assert_eq(listed[1], "/srv/api/.env.production")
  assert_eq(listed[2], "/srv/api/.env.local")
  assert_eq(listed[3], "/srv/api/.env.production.local")
}

///|
test "files skips .env.local in test mode" {
  let listed = @dotenv.files("/srv/api", "test")
  assert_eq(listed[0], "/srv/api/.env")
  assert_eq(listed[1], "/srv/api/.env.test")
  assert_eq(listed[2], "/srv/api/.env.test.local")
  assert_eq(listed.length(), 3)
}

///|
test "later files override earlier ones" {
  let dir = "/tmp/dotenv-test-order"
  let files : Array[(String, String)] = [
    (".env", "A=base\nB=base\n"),
    (".env.production", "A=prod\n"),
    (".env.local", "B=local\n"),
  ]
  setup(dir, files)
  let out = @dotenv.load(dir, "production", no_env)
  assert_eq(out.get("A"), Some("prod"))
  assert_eq(out.get("B"), Some("local"))
  teardown(dir, files)
}

///|
test "a missing file is not an error" {
  let dir = "/tmp/dotenv-test-missing"
  let _ = try @fs.create_dir(dir) catch {
    _ => ()
  } noraise {
    _ => ()
  }
  let out = @dotenv.load(dir, "production", no_env)
  assert_eq(out.length(), 0)
  let _ = try @fs.remove_dir(dir) catch {
    _ => ()
  } noraise {
    _ => ()
  }
}

///|
test "expansion does not look into other files" {
  let dir = "/tmp/dotenv-test-scope"
  let files : Array[(String, String)] = [
    (".env", "P=plain\n"),
    (".env.local", "R=${P}-tail\n"),
  ]
  setup(dir, files)
  let out = @dotenv.load(dir, "production", no_env)
  // Bun 的实测行为：.env.local 里引用 .env 的键，展开成空
  assert_eq(out.get("R"), Some("-tail"))
  teardown(dir, files)
}

///|
test "the process environment wins over every file" {
  let dir = "/tmp/dotenv-test-envwin"
  let files : Array[(String, String)] = [
    (".env", "A=from-file\n"),
    (".env.production", "A=from-file-again\n"),
  ]
  setup(dir, files)
  let out = @dotenv.load(dir, "production", env_with("A", "from-env"))
  assert_eq(out.get("A"), Some("from-env"))
  teardown(dir, files)
}

///|
test "load is lenient about a bad line" {
  let dir = "/tmp/dotenv-test-lenient"
  let files : Array[(String, String)] = [(".env", "JUSTAKEY\nA=1\n")]
  setup(dir, files)
  let out = @dotenv.load(dir, "production", no_env)
  assert_eq(out.get("A"), Some("1"))
  teardown(dir, files)
}

///|
test "load_strict reports the bad line" {
  let dir = "/tmp/dotenv-test-strict"
  let files : Array[(String, String)] = [(".env", "A=1\nJUSTAKEY\n")]
  setup(dir, files)
  let outcome = try {
    ignore(@dotenv.load_strict(dir, "production", no_env))
    "no error"
  } catch {
    e => e.describe()
  }
  assert_true(outcome.contains("line 2"))
  assert_true(outcome.contains(".env"))
  teardown(dir, files)
}

///|
test "test mode ignores .env.local" {
  let dir = "/tmp/dotenv-test-mode"
  let files : Array[(String, String)] = [
    (".env", "A=base\n"),
    (".env.local", "A=local\n"),
    (".env.test", "B=test\n"),
  ]
  setup(dir, files)
  let out = @dotenv.load(dir, "test", no_env)
  assert_eq(out.get("A"), Some("base"))
  assert_eq(out.get("B"), Some("test"))
  teardown(dir, files)
}

///|
test "an unreadable file is reported as Unreadable" {
  // 目录存在但同名条目是目录时读不出内容
  let dir = "/tmp/dotenv-test-unreadable"
  let target = dir + "/.env"
  let _ = try @fs.create_dir(dir) catch {
    _ => ()
  } noraise {
    _ => ()
  }
  let _ = try @fs.create_dir(target) catch {
    _ => ()
  } noraise {
    _ => ()
  }
  let outcome = try {
    ignore(@dotenv.load(dir, "production", no_env))
    "no error"
  } catch {
    e => e.describe()
  }
  assert_true(outcome.contains("cannot read"))
  let _ = try @fs.remove_dir(target) catch {
    _ => ()
  } noraise {
    _ => ()
  }
  let _ = try @fs.remove_dir(dir) catch {
    _ => ()
  } noraise {
    _ => ()
  }
}
