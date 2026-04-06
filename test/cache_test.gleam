import gleam/string
import mxpak/cache
import mxpak/cache/integrity
import mxpak/cache/store
import simplifile

// === integrity 테스트 ===

pub fn sha256_deterministic_test() {
  let hash1 = integrity.sha256(<<"hello":utf8>>)
  let hash2 = integrity.sha256(<<"hello":utf8>>)
  let assert True = hash1 == hash2
}

pub fn sha256_different_inputs_test() {
  let hash1 = integrity.sha256(<<"hello":utf8>>)
  let hash2 = integrity.sha256(<<"world":utf8>>)
  let assert True = hash1 != hash2
}

pub fn sha256_known_value_test() {
  // SHA-256("hello") = 2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824
  let hash = integrity.sha256(<<"hello":utf8>>)
  let assert True =
    hash == "2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824"
}

pub fn sha256_hex_length_test() {
  let hash = integrity.sha256(<<"test":utf8>>)
  let assert True = string.length(hash) == 64
}

pub fn verify_success_test() {
  let data = <<"verify me":utf8>>
  let hash = integrity.sha256(data)
  let assert True = integrity.verify(data, hash)
}

pub fn verify_failure_test() {
  let assert True = integrity.verify(<<"data":utf8>>, "wrong_hash") == False
}

// === store 테스트 ===

pub fn store_put_and_has_test() {
  let data = <<"test zip data":utf8>>
  let entries = [#("file.txt", <<"content":utf8>>)]

  let assert Ok(#(_dir, hash)) = store.put(data, entries)
  let assert True = store.has(hash)

  // 정리
  let _ = simplifile.delete(store.cache_path(hash))
  Nil
}

pub fn store_has_missing_test() {
  let assert True = store.has("nonexistent_hash_123") == False
}

// === cache 통합 테스트 ===

pub fn cache_roundtrip_test() {
  let data = <<"roundtrip test":utf8>>
  let entries = [#("test.xml", <<"<widget/>":utf8>>)]

  let hash = cache.hash(data)
  let assert True = cache.verify(data, hash)

  let assert Ok(#(_, stored_hash)) = cache.put(data, entries)
  let assert True = hash == stored_hash
  let assert True = cache.has(hash)

  // 복원
  let target = "build/test_tmp/cache_restore"
  let _ = simplifile.create_directory_all(target)
  let assert Ok(_) = cache.restore(hash, target)

  let assert Ok(content) = simplifile.read_bits(target <> "/test.xml")
  let assert True = content == <<"<widget/>":utf8>>

  // 정리
  let _ = simplifile.delete(store.cache_path(hash))
  let _ = simplifile.delete(target)
  Nil
}
