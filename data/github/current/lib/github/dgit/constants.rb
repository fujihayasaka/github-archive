# typed: true
# frozen_string_literal: true

module GitHub
  class DGit
    # Checksum version to request for dgit operations
    DGIT_CURRENT_CHECKSUM_VERSION = 5
    # Oldest version still considered reliable
    # TODO: NOT YET IMPLEMENTED
    DGIT_MINIMUM_CHECKSUM_VERSION = 0
    # Sentinel host value for identifying gists in DGit.
    DGIT_GIST_HOST = "dgit."

    # Error codes returned from rsync that are worth retrying.
    # These are a little bit arbitrary.  The goal is to retry transient
    # failures in cases where the retry won't do more harm than good.  So
    # we don't retry out-of-memory, protocol mismatch, syntax error, etc.
    # But we do retry timeouts, signals, and changes to the underlying
    # file set.
    RETRYABLE_RSYNC_RESULTS = [
      20,  # Received SIGUSR1 or SIGINT
      23,  # Partial transfer due to error
      24,  # Partial transfer due to vanished source files
      30,  # Timeout in data send/receive
    ]

    # The maximum gap between the fraction of free disk space on the
    # emptiest host and on the fullest host.  See DGit.disk_stats for
    # the preceise definition.  The idea here is to keep all hosts at
    # about the same percentage of disk space free, but with a gap for
    # hysteresis.
    MAX_DISK_SPACE_SPREAD = 0.1

    # This is the value the disk_stats RPC returns if it is unable to
    # determine available disk space on the given DFS host.
    DGIT_DISK_STATS_INVALID = [0, 1]
  end
end
