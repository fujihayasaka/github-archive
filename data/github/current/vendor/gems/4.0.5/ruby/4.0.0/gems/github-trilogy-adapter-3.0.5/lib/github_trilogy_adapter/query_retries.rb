# frozen_string_literal: true

module GitHubTrilogyAdapter
  module QueryRetries
    # We reconnect and retry queries in a lot more places than Rails does by
    # default. It's not strictly safe, but it allows us to handle the frequent
    # GLB restarts that terminate all our connections.
    #
    # If rails has already decided the query is safe to retry, we'll trust its
    # judgement. Otherwise we can only retry if it's not a SCHEMA query (because
    # we could theoretically get into an infinite loop of reconnecting and
    # failing to configure the new connection) or a TRANSACTION query (because
    # reconnecting and retrying a COMMIT or ROLLBACK makes no sense and would be
    # confusing or incorrect).
    def allow_retry
      @allow_retry || (name != "SCHEMA" && name != "TRANSACTION")
    end
  end
end
