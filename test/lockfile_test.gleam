import gleam/dict
import gleam/option.{None, Some}
import mxpak/lockfile
import simplifile

pub fn write_and_read_test() {
  let dir = "build/test_tmp/lock1"
  let _ = simplifile.create_directory_all(dir)

  let entries =
    dict.new()
    |> dict.insert(
      "DataGrid",
      lockfile.LockEntry(
        "2.5.0",
        "abc123hash",
        Some(12_345),
        Some("w/id/2.5.0/DG.mpk"),
        False,
      ),
    )
    |> dict.insert(
      "Charts",
      lockfile.LockEntry("1.0.0", "def456hash", None, None, True),
    )

  let assert Ok(_) = lockfile.write(dir, entries)
  let assert Ok(lock) = lockfile.read(dir)

  let assert Ok(dg) = lockfile.get_entry(lock, "DataGrid")
  let assert True = dg.version == "2.5.0"
  let assert True = dg.hash == "abc123hash"
  let assert Some(12_345) = dg.content_id
  let assert Some("w/id/2.5.0/DG.mpk") = dg.s3_id
  let assert True = dg.classic == False

  let assert Ok(ch) = lockfile.get_entry(lock, "Charts")
  let assert True = ch.version == "1.0.0"
  let assert True = ch.classic == True
  let assert None = ch.content_id

  let _ = simplifile.delete(dir)
  Nil
}

pub fn exists_true_test() {
  let dir = "build/test_tmp/lock2"
  let _ = simplifile.create_directory_all(dir)
  let _ = simplifile.write(dir <> "/mxpak.lock", "# empty\n")
  let assert True = lockfile.exists(dir)
  let _ = simplifile.delete(dir)
  Nil
}

pub fn exists_false_test() {
  let assert True = lockfile.exists("build/test_tmp/no_lock") == False
}

pub fn read_missing_test() {
  let assert Error(_) = lockfile.read("build/test_tmp/no_lock")
}

pub fn remove_test() {
  let dir = "build/test_tmp/lock3"
  let _ = simplifile.create_directory_all(dir)
  let _ = simplifile.write(dir <> "/mxpak.lock", "# test\n")
  let assert Ok(_) = lockfile.remove(dir)
  let assert True = lockfile.exists(dir) == False
  let _ = simplifile.delete(dir)
  Nil
}

pub fn quoted_key_test() {
  let dir = "build/test_tmp/lock4"
  let _ = simplifile.create_directory_all(dir)

  let entries =
    dict.new()
    |> dict.insert(
      "Data Widgets",
      lockfile.LockEntry("1.0.0", "hash", None, None, False),
    )

  let assert Ok(_) = lockfile.write(dir, entries)
  let assert Ok(content) = simplifile.read(dir <> "/mxpak.lock")
  let assert True = {
    content
    |> string_contains("[widgets.\"Data Widgets\"]")
  }

  let assert Ok(lock) = lockfile.read(dir)
  let assert Ok(entry) = lockfile.get_entry(lock, "Data Widgets")
  let assert True = entry.version == "1.0.0"

  let _ = simplifile.delete(dir)
  Nil
}

import gleam/string

fn string_contains(haystack: String, needle: String) -> Bool {
  string.contains(haystack, needle)
}
