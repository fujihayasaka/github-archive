# typed: true
# frozen_string_literal: true

module GitHub
  class NullStatsD
    def initialize; @shards = []; end
    def timing(k, v, s = 1) end
    def histogram(k, v, s = 1) end
    def distribution(k, v, s = 1) end
    def count(k, v, s = 1) end
    def time(name, s = 1) yield end
    def increment(k, v = 1) end
    def decrement(k, v = 1) end
    def gauge(k, v) end
    def add_shard(*args) end
    def enable_buffering(b = nil) end
    def disable_buffering() end
    def flush_all() end
    attr_accessor :shards
    attr_accessor :namespace
  end
end
