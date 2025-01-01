# typed: true
# frozen_string_literal: true

module GitHub
  module Redis
    autoload :CardinalityCounter, "github/redis/cardinality_counter"
    autoload :Mutex, "github/redis/mutex"
    autoload :MutexGroup, "github/redis/mutex_group"
    autoload :ConcurrencySafeMutex, "github/redis/concurrency_safe_mutex"
  end
end
