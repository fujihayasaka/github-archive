# typed: true
# frozen_string_literal: true

module GitHub
  class BufferedStatsMiddleware
    DEFAULT_BUFFER_SIZE = 4000

    def initialize(app, buffer_size = DEFAULT_BUFFER_SIZE)
      @app = app
      @buffer_size = buffer_size
    end

    def gather_flush_stats
      flushes = GitHub.stats.shards.sum { |c| c.flush_count + 1 } if GitHub.enterprise?
      GitHub.stats.histogram("metrics.flush", flushes) if GitHub.enterprise?
    end

    def call(env)
      GitHub.stats.enable_buffering(@buffer_size) if GitHub.enterprise?
      @app.call(env)
    ensure
      gather_flush_stats
      # Disabling the buffering will flush all remaining stats
      GitHub.stats.disable_buffering if GitHub.enterprise?
    end
  end
end
