# rubocop:disable Style/FrozenStringLiteralComment
# typed: true

module GitRPC
  class Client
    # Public: Show reflog information
    #
    # ref           - Limit results to a specific ref.
    # limit         - Show at most <num> log entries. Defaults to 50.
    #                 If `chronological` and `newer_than` are both specified, then the oldest <num> entries are returned.
    #                 Otherwise, the newest <num> entries are returned.
    # pagination    - Show whether previous/next pages of log entries are available.
    # squash        - Squash adjacent similar entries
    # before_oid    - Only show entries where the OID before the push was <oid>.
    # after_oid     - Only show entries where the OID after the push was <oid>.
    # newer_than    - Only show entries newer than <time>.
    # older_than    - Only show entries older than <time>.
    # condensed     - Write condensed output more suitable for humans.
    # sanitized     - Sanitize refs in condensed output.
    # no_sanitized  - Do not sanitize refs in condensed output.
    # no_cprmcs     - Omit pull request merge and rebase references.
    # no_pr_heads   - Omit pull request head references.
    # iso_times     - Convert unixtime values to ISO8601 formatted times.
    # chronological - Emit output in chronological order.
    def push_log(options = {})
      send_message(:push_log, **options)
    end
  end
end
