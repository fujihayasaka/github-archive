# typed: true
# frozen_string_literal: true

module Team::ParentChange
  class Lock < GitHub::Redis::MutexGroup
    TIMEOUT_SECS   = 300    # So the lock gets cleared if the process is killed after it's been acquired (i.e. in case of a request timeout)
    WAIT_SECS      = 2      # Used when `lock_with_retry` or `lock` are called. It will try up to this time in seconds to acquire the lock. (Only used in jobs)
    SLEEP_SECS     = 0.2    # Sleep 200 millis if `lock_with_retry` or `lock` are called.

    def initialize(org_id:, timeout: TIMEOUT_SECS, wait: WAIT_SECS, sleep: SLEEP_SECS)
      super("team/parent_change", org_id, timeout: timeout, wait: wait, sleep: sleep)
    end

    def try_lock!
      acquired = try_lock
      if !acquired
        raise CannotAcquireLockError
      end
      acquired
    end
  end
end
