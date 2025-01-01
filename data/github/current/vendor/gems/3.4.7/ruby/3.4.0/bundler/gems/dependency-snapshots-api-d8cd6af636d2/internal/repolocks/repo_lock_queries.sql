
-- name: GetLock :one
SELECT *
from ds_repo_locks
where repository_id = ?
and   lock_name = ?;

-- name: CreateLock :exec
INSERT IGNORE INTO ds_repo_locks (repository_id, lock_name) VALUES (?, ?);

-- name: Unlock :execrows
UPDATE ds_repo_locks set
  lock_id = null,
  expire_at = null
where repository_id = ?
  and   lock_name = ?
  and   lock_id = ?;

-- name: UnlockExpired :exec
UPDATE ds_repo_locks set
  lock_id = null,
  expire_at = null
where repository_id = ?
and   lock_name = ?
and   lock_id is not null
and   expire_at < now();

-- name: Lock :execrows
UPDATE ds_repo_locks set
  lock_id = ?,
  expire_at = ?
where repository_id = ?
and   lock_name = ?
and   lock_id is null;


-- name: ReLock :execrows
UPDATE ds_repo_locks set
  expire_at = ?
where repository_id = ?
and lock_name = ?
and lock_id = ?
and expire_at > now();


-- example of bulk inserts
-- after running this, need an explicit
--      SHOW COUNT(*) WARNINGS;
-- and verify it's zero
-- name: CreateManyLocks :copyfrom
-- INSERT IGNORE INTO ds_repo_locks (repository_id, lock_name) VALUES (?, ?);
