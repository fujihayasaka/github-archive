# typed: true
# frozen_string_literal: true

require "github/statsd"

# Statsd client that only sends stats that have been whitelisted.
#
#     $stats = GitHub::Statsd::Whitelist.new(%w(
#       pages.failure
#       unicorn.{browser,ajax}.requests_per_second
#       whitelisted.*
#     ))
#
#     $stats.increment("whitelisted.key")
#     $stats.increment("not.whitelisted") # ignored
#
# The whitelist is an array of strings. Expansion (`{a,b}`) and wildcards (`*`)
# are supported, but note that unlike Graphite, `*` will match any character,
# including a period.
module GitHub
  class Statsd::Whitelist < Statsd
    def initialize(whitelist = [])
      super(nil)
      @whitelist = whitelist
    end

    def send(stat, *args)
      super if whitelisted?(stat)
    end

    def whitelisted?(stat)
      @whitelist.any? { |pattern| File.fnmatch(pattern, stat, File::FNM_EXTGLOB) }
    end
  end
end
