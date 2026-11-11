# typed: true
# frozen_string_literal: true

require "github/dogstats"

# Dogstats client that only sends stats that have been allowlisted.
# While this implementation is generic, it's primarily used in GitHub Enterprise
# environments where we want to limit the metrics to control the volume at the source.
#
#     dogstats = GitHub::Dogstats::Allowlist.new(%w(
#       pages.failure
#       unicorn.{browser,ajax}.requests_per_second
#       allowlisted.*
#     ), "localhost", 8125)
#
#     dogstats.increment("allowlisted.key")
#     dogstats.increment("not.allowlisted") # ignored
#
# The allowlist is an array of strings. Expansion (`{a,b}`) and wildcards (`*`)
# are supported. `*` will match any character, including a period.
module GitHub
  class Dogstats::Allowlist < Dogstats
    def initialize(allowlist = [], host = nil, port = nil, **kwargs)
      super(host, port, **kwargs)
      @allowlist = allowlist
    end

    private

    # Override the internal send_stats method that all metric methods use
    def send_stats(stat, delta, type, opts = {})
      if allowlisted?(stat)
        super(stat, delta, type, opts)
      end
      # If not allowlisted, do nothing - metric is blocked
    end

    def allowlisted?(stat)
      stat = stat.to_s
      @allowlist.any? { |pattern| File.fnmatch(pattern, stat, File::FNM_EXTGLOB) }
    end
  end
end
