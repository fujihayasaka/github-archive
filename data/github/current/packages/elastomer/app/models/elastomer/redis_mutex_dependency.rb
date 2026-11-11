# typed: true
# frozen_string_literal: true

module Elastomer
  module RedisMutexDependency
    extend T::Helpers
    include GitHub::Memoizer
    abstract!

    attr_reader :mutex_timeout
    attr_reader :mutex_wait

    sig { abstract.returns(String) }
    def group_key; end

    sig { params(timeout: Integer, wait: Integer, queue: T.nilable(Symbol)).returns(GitHub::Redis::MutexGroup) }
    def mutex(timeout: 60, wait: 10, queue: nil)
      key = mutex_key
      key = "#{key}/#{queue}" if queue
      GitHub::Redis::MutexGroup.new(group_key, key, timeout: timeout, wait: wait, sleep: mutex_sleep)
    end

    sig { returns(String) }
    def mutex_key
      "#{group_key}/mutex"
    end

    # Returns the time to sleep between attempts to acquire the mutex.
    # The value includes a jitter to avoid repeated attempts by multiple jobs
    # to obtain the mutex at the same time.
    def mutex_sleep
      # Use a shorter base sleep time when fast model lookup is enabled
      base_sleep_time = 0.3

      # Add up to 100ms of jitter to the base sleep time
      base_sleep_time + (Kernel.rand * 0.1).ceil(2)
    end
  end
end
