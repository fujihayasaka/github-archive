class Lock < ApplicationRecord
  self.table_name = "dg_locks"

  scope :by_name, -> (lockname) { where(lockname: lockname) }

  def self.release(lockname)
    # NOTE: unless specifically parameterized, the lock management script does not poll
    #       for expiration of a held lock; the check is a one-shot per process when "--wait=false"
    #       is used.
    #       https://github.com/github/dependency-graph-api/blob/master/go/mysql-lock/main.go#L65
    #       https://github.com/github/dependency-graph-api/blob/master/config/kubernetes/workers/cronjobs/sync-vulnerabilities.yaml#L24
    #       "expires" timestamp must also account for the current "lease" value:
    #       https://github.com/github/dependency-graph-api/blob/master/go/mysql-lock/main.go#L155
    #
    #       ...to avoid unexpected interactions, we can just delete the lock since the mangement script will recreate it
    self.delete_by(lockname: lockname)
  end
end
