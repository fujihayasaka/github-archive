# typed: true
# frozen_string_literal: true

require "github/statsd"

# Statsd client that only sends stats that have been allowlisted.
#
#     $stats = GitHub::Statsd::Allowlist.new(%w(
#       pages.failure
#       unicorn.{browser,ajax}.requests_per_second
#       allowlisted.*
#     ))
#
#     $stats.increment("allowlisted.key")
#     $stats.increment("not.allowlisted") # ignored
#
# The allowlist is an array of strings. Expansion (`{a,b}`) and wildcards (`*`)
# are supported, but note that unlike Graphite, `*` will match any character,
# including a period.
module GitHub
  class Statsd::Allowlist < Statsd
    def initialize(allowlist = [])
      super(nil)
      @allowlist = allowlist
    end

    def send(stat, *args)
      super if allowlisted?(stat)
    end

    def allowlisted?(stat)
      @allowlist.any? { |pattern| File.fnmatch(pattern, stat, File::FNM_EXTGLOB) }
    end
  end
end
