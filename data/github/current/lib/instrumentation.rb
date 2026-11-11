# typed: true
# frozen_string_literal: true

require "active_support/core_ext/module/attribute_accessors_per_thread"

module Instrumentation
  autoload :AttachableSubscriber, "instrumentation/attachable_subscriber"
  autoload :MockService, "instrumentation/mock_service"
  autoload :Model, "instrumentation/model"
  autoload :ModelInstrumenter, "instrumentation/model_instrumenter"
  autoload :NullService, "instrumentation/null_service"
  autoload :QuerySubscriber, "instrumentation/query_subscriber"
  autoload :TestCase, "instrumentation/test_case"
  autoload :TestSubscription, "instrumentation/test_subscription"
  autoload :TransactionSubscriber, "instrumentation/transaction_subscriber"
  autoload :SampledChecker, "instrumentation/sampled_checker"
  autoload :SampledSubscriber, "instrumentation/sampled_subscriber"
  autoload :StatsReporter, "instrumentation/stats_reporter"

  def self.track_time(metric, tags: [])
    before = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    value = yield
    after = Process.clock_gettime(Process::CLOCK_MONOTONIC)

    GitHub.dogstats.distribution(metric, (after - before) * 1000.0, tags: tags)
    value
  end

  thread_mattr_accessor :suppressed

  def self.suppressing
    was_suppressed, self.suppressed = suppressed, true
    yield
  ensure
    self.suppressed = was_suppressed
  end

  def self.suppressed?
    suppressed
  end
end
