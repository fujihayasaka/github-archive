# typed: strict
# frozen_string_literal: true

module RetroactiveImmutability
  # Per-repository lock for the retroactive immutability migration.
  #
  # The lock *is* the migration's own KV status record: acquiring it is a single
  # atomic GitHub::KV#setnx on the status key, so only one run can hold it for a
  # repository at a time. While a run makes progress it keeps rewriting that
  # record (see MigrationState#write_status), which refreshes the key's TTL, so
  # the lock renews itself for free with no separate lease bookkeeping.
  #
  # Crash safety: if a worker dies without releasing, the record expires after
  # MigrationState::TTL and the lock is reclaimed automatically (setnx prunes the
  # expired row before re-inserting). A single acquire is meant to cover one
  # bounded unit of work (e.g. a batch of releases); long migrations span many
  # acquires via the persisted cursor, so the lock is only ever held briefly.
  class Lock
    LockHeldError = Class.new(StandardError)

    # Acquire the lock for repo and run the block while holding it.
    #
    # The block is handed the run's started_at; pass it through to
    # MigrationState.write so the status record (and thus the lock) stays fresh
    # and the eventual release can confirm it still owns the record.
    #
    # Raises LockHeldError if another run currently holds the lock. The lock is
    # released when the block returns or raises; if the worker dies first, the
    # status record expires on its own (see class docs).
    sig { params(repo: ::Repository, blk: T.proc.params(started_at: Time).returns(T.untyped)).returns(T.untyped) }
    def self.acquire(repo, &blk)
      started_at = Time.now.utc

      unless MigrationState.claim(repo, started_at: started_at)
        raise LockHeldError, "A retroactive immutability migration is already running for repository #{repo.id}"
      end

      begin
        blk.call(started_at)
      ensure
        MigrationState.release(repo, started_at: started_at)
      end
    end
  end
end
