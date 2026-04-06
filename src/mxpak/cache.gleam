// 캐시 통합 인터페이스 — CAS 조회/저장/링크/정리

import mxpak/cache/integrity
import mxpak/cache/store

/// 바이너리 데이터의 SHA-256 해시 계산
pub fn hash(data: BitArray) -> String {
  integrity.sha256(data)
}

/// 해시 무결성 검증
pub fn verify(data: BitArray, expected_hash: String) -> Bool {
  integrity.verify(data, expected_hash)
}

/// 캐시에 해당 해시가 존재하는지 확인
pub fn has(hash: String) -> Bool {
  store.has(hash)
}

/// 바이너리 + 추출된 엔트리를 캐시에 저장
pub fn put(
  data: BitArray,
  entries: List(#(String, BitArray)),
) -> Result(#(String, String), String) {
  store.put(data, entries)
}

/// 캐시에서 프로젝트로 복사
pub fn restore(hash: String, target_dir: String) -> Result(Nil, String) {
  store.link_to_project(hash, target_dir)
}

/// 캐시의 original.mpk를 대상 경로에 하드 링크 (mpk 모드용)
pub fn restore_mpk(hash: String, target_path: String) -> Result(Nil, String) {
  store.restore_mpk(hash, target_path)
}

/// 캐시 디렉토리 경로 (해시 기반)
pub fn path(hash: String) -> String {
  store.cache_path(hash)
}

/// 전체 캐시 삭제
pub fn clean() -> Result(Nil, String) {
  store.clean()
}
