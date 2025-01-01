# typed: false
# frozen_string_literal: true

require "test_helper"

class DefaultsError < StandardError; end
class LongWaitError < StandardError; end
class ShortWaitTenAttemptsError < StandardError; end
class ExponentialWaitTenAttemptsError < StandardError; end
class CustomCatchError < StandardError; end
class DiscardableError < StandardError; end
class CustomDiscardableError < StandardError; end
class StatsError < StandardError; end

class JobBuffer
  def self.add(value)
    values << value
  end

  def self.values
    @values ||= []
  end
end

class TestLogCapturingJob < ApplicationJob
  mattr_accessor :logging_context, instance_writer: false, instance_reader: false

  before_perform { self.class.logging_context = GitHub.logger.named_tags }
end

class TestRetryApplicationJob < TestLogCapturingJob
  map_to_service :wall_e

  rescue_from StatsError do |_error|
    JobBuffer.add("Rescued from StatsError")
  end

  retry_on DefaultsError, attempts: 5
  retry_on ShortWaitTenAttemptsError, wait: 1.second, attempts: 10
  retry_on LongWaitError, wait: 1.hour, attempts: 10
  retry_on ExponentialWaitTenAttemptsError, wait: :polynomially_longer, attempts: 10

  retry_on CustomCatchError do |job, error|
    JobBuffer.add("Dealt with a job that failed to retry in a custom way after #{job.arguments.second} attempts. Message: #{error.message}")
  end

  retry_on ActiveJob::DeserializationError do |job, _error|
    JobBuffer.add("Failed to execute after #{job.executions} attempts")
  end

  discard_on DiscardableError
  discard_on CustomDiscardableError do |_job, error|
    JobBuffer.add("Dealt with a job that was discarded in a custom way. Message: #{error.message}")
  end

  def failbot_context
    { special_failbot_stuff: 1 }
  end

  def perform(raising, attempts, obj = nil)
    if executions < attempts
      JobBuffer.add("Raised #{raising} for the #{executions.ordinalize} time")
      raise raising.constantize
    else
      JobBuffer.add("Successfully completed job")
    end
  end
end

class TestRescueUnableToLock < ApplicationJob
  ATTEMPTS = 2

  retry_on GitHub::Restraint::UnableToLock, attempts: ATTEMPTS

  def perform
    JobBuffer.add("Raised GitHub::Restraint::UnableToLock")
    raise GitHub::Restraint::UnableToLock
  end
end

class TestRetryOnDirtyExitApplicationJob < ApplicationJob
  #retries on Aqueduct::Worker::JobKilled
  retry_on_dirty_exit

  def perform(raises, attempts)
    if executions < attempts
      JobBuffer.add("Raised #{raises} for the #{executions.ordinalize} time")
      raise raises.constantize
    else
      JobBuffer.add("Successfully completed job")
    end
  end
end

class TestRetryOnDirtyExitCustomHandlingJob < TestRetryOnDirtyExitApplicationJob
  #retries on Aqueduct::Worker::JobKilled
  retry_on_dirty_exit do |job, error|
    JobBuffer.add("Retrying failed after #{job.executions} attempts. Message: #{error.message}")
  end
end

class TestRetryOnRecoverableExceptionsApplicationJob < ApplicationJob
  #retries on UnavailableExceptions defined in lib/resiliency/response.rb
  MAX_ATTEMPTS = 3
  retry_on_recoverable_exceptions attempts: MAX_ATTEMPTS

  def perform(raises, attempts)
    if executions < attempts
      JobBuffer.add("Raised #{raises} for the #{executions.ordinalize} time")
      raise raises.constantize
    else
      JobBuffer.add("Successfully completed job")
    end
  end
end

class TestRetryOnRecoverableExceptionsCustomHandlingJob < ApplicationJob
  #retries on UnavailableExceptions defined in lib/resiliency/response.rb
  MAX_ATTEMPTS = 3
  retry_on_recoverable_exceptions attempts: MAX_ATTEMPTS do |job, error|
    JobBuffer.add("Dealt with a job that failed to retry in a custom way after #{job.executions} attempts. Message: #{error.message}")
  end

  def perform(raises, attempts)
    if executions < attempts
      JobBuffer.add("Raised #{raises} for the #{executions.ordinalize} time")
      raise raises.constantize
    else
      JobBuffer.add("Successfully completed job")
    end
  end
end

class TestFailbotContextRetryJob < ApplicationJob
  retry_on DefaultsError

  def failbot_context
    raise DefaultsError
  end
end

class TestFailbotContextDiscardJob < ApplicationJob
  discard_on DiscardableError

  def failbot_context
    raise DiscardableError
  end
end

class TestRetryWithRescueFromJob < TestRetryApplicationJob
  rescue_from StandardError do
    JobBuffer.add("Rescued from StandardError in subclass")
  end
end

class TestRetryDeserializationErrorJob < ApplicationJob
  retry_on ActiveJob::DeserializationError do |job, _error|
    JobBuffer.add("Failed to execute after #{job.executions} attempts")
  end

  def perform(ar_model)
    JobBuffer.add("Successfully completed job")
  end

  def deserialize(...)
    super
  ensure
    JobBuffer.add("Raised DeserializationError for the #{executions.ordinalize} time")
  end
end

class TestRetryBasedOnCauseJob < TestRetryApplicationJob
  def perform(*args)
    begin
      raise DefaultsError.new
    rescue DefaultsError
      raise TypeError
    end
  end
end

class TestNoCounterApplicationJob < ApplicationJob
  map_to_service :wall_e

  def serialize
    super.tap { |obj| obj["executions"] = nil }
  end

  def perform
    JobBuffer.add("Successfully completed job")
  end
end

class TestCustomTagsJob < ApplicationJob
  def stats_tags
    ["event_type:#{arguments.first}"]
  end

  def perform(event_type)
    JobBuffer.add("Successfully completed job")
  end
end

class TestFailsPerformJob < ApplicationJob
  def perform
    raise "perform failed"
  end
end

class TestFailsEnqueueJob < ApplicationJob
  def deserialize(*)
    raise "enqueue failed"
  end
end

class TestRecordNotFoundJob < ApplicationJob
  discard_on ActiveRecord::RecordNotFound do
    JobBuffer.add("Discarded after AR NotFound")
  end
end

class TestSimpleJob < TestLogCapturingJob
  map_to_service :background_jobs

  def perform
  end

  def logging_context
    super.merge({ "gh.stuff" => "hello" })
  end
end

class TestSimpleDbCallSourceJob < ApplicationJob
  attr_accessor :db_call_source_tags

  def perform
    @db_call_source_tags = GitHub.context[:db_call_source_datadog_tags]
  end
end

class TestSimpleParameterizedJob < TestLogCapturingJob
  def perform(id)
  end
end

class TestSimpleParameterizedTwoJob < TestLogCapturingJob
  def perform(id)
  end
end

class PackageContextTestJob < ApplicationJob
  queue_as :package_context_test

  def perform
    raise "ApplicationJob package context was:#{GitHub.context[:package]}, but expected test-package" unless GitHub.context[:package] == "test-package"
  end
end

class GHContextTestJob < ApplicationJob
  def perform
    raise "context is null!" if GH.context == GH::Context::NULL_CONTEXT
  end
end

class ApplicationJobTest < GitHub::TestCase
  include ActiveSupport::Testing::TimeHelpers
  include ActiveJob::TestHelper

  setup do
    JobBuffer.values.clear
    TestLogCapturingJob.descendants.each do |klass|
      klass.logging_context = nil
    end
  end

  test "collects the expected base stats in around_perform" do
    GitHub.stubs(:dogstats).returns(GitHub::MemoryDogstatsD.new)

    TestNoCounterApplicationJob.perform_now
    increment_tags = GitHub.dogstats.increments("active_job.performed").first.tags
    assert_includes increment_tags, "class:test_no_counter_application_job"
    assert_includes increment_tags, "queue:default"
    assert_includes increment_tags, "adapter:aqueduct"

    assert_includes increment_tags, "class:test_no_counter_application_job"
    assert_includes increment_tags, "queue:default"
    assert_includes increment_tags, "adapter:aqueduct"

    unless GitHub.enterprise?
      assert_includes increment_tags, "catalog_service:github/wall_e"

      assert_equal "github/wall_e", Failbot.squash_contexts(Failbot.context)["catalog_service"]
      assert_equal "github/wall_e", Audit.context[:catalog_service]
      assert_equal "github/wall_e", GitHub.context[:catalog_service]
    end
  end

  test "adds db call source datadog tag to context" do
    job = TestSimpleDbCallSourceJob.new
    job.perform_now

    class_name = job.class.name&.underscore
    expected_tags = ["source_type:job", "job:#{class_name}", "source:job-#{class_name}"]

    assert_same_elements expected_tags, job.db_call_source_tags
  end

  test "collects the expected base stats in around_enqueue" do
    GitHub.stubs(:dogstats).returns(GitHub::MemoryDogstatsD.new)

    TestNoCounterApplicationJob.perform_later
    increment_tags = GitHub.dogstats.increments("active_job.enqueued").first.tags
    assert_includes increment_tags, "class:test_no_counter_application_job"
    assert_includes increment_tags, "queue:default"
    assert_includes increment_tags, "adapter:aqueduct"

    assert_includes increment_tags, "class:test_no_counter_application_job"
    assert_includes increment_tags, "queue:default"
    assert_includes increment_tags, "adapter:aqueduct"
    assert_includes increment_tags, "catalog_service:github/wall_e" unless GitHub.enterprise?
  end

  test "collects expected stats when enqueued with a wait" do
    GitHub.stubs(:dogstats).returns(GitHub::MemoryDogstatsD.new)

    TestNoCounterApplicationJob.set(wait: 1.second).perform_later
    increment_tags = GitHub.dogstats.increments("active_job.enqueued_at").first.tags
    assert_includes increment_tags, "class:test_no_counter_application_job"
    assert_includes increment_tags, "queue:default"
    assert_includes increment_tags, "adapter:aqueduct"

    assert_includes increment_tags, "class:test_no_counter_application_job"
    assert_includes increment_tags, "queue:default"
    assert_includes increment_tags, "adapter:aqueduct"
    assert_includes increment_tags, "catalog_service:github/wall_e" unless GitHub.enterprise?
  end

  test "collects the expected base stats with rescue_from" do
    GitHub.stubs(:dogstats).returns(GitHub::MemoryDogstatsD.new)

    TestRetryApplicationJob.perform_now("StatsError", 2)
    increment_tags = GitHub.dogstats.increments("active_job.performed").first.tags
    assert_includes increment_tags, "class:test_retry_application_job"
    assert_includes increment_tags, "queue:default"
    assert_includes increment_tags, "adapter:aqueduct"

    assert_includes increment_tags, "class:test_retry_application_job"
    assert_includes increment_tags, "queue:default"
    assert_includes increment_tags, "adapter:aqueduct"

    unless GitHub.enterprise?
      assert_includes increment_tags, "catalog_service:github/wall_e"

      assert_equal "github/wall_e", Failbot.squash_contexts(Failbot.context)["catalog_service"]
      assert_equal "github/wall_e", Audit.context[:catalog_service]
      assert_equal "github/wall_e", GitHub.context[:catalog_service]
    end

    assert_equal [
      "Raised StatsError for the 1st time",
      "Rescued from StatsError",
    ], JobBuffer.values
  end

  test "base stats collected includes custom tags" do
    GitHub.stubs(:dogstats).returns(GitHub::MemoryDogstatsD.new)

    perform_enqueued_jobs(only: [TestCustomTagsJob]) do
      TestCustomTagsJob.perform_later("test_event")
    end

    assert_includes GitHub.dogstats.increments("active_job.enqueued").first.tags, "event_type:test_event"
    assert_includes GitHub.dogstats.increments("active_job.performed").first.tags, "event_type:test_event"
    assert_includes GitHub.dogstats.distributions("active_job.enqueue.dist.time").first.tags, "event_type:test_event"
    assert_includes GitHub.dogstats.distributions("active_job.perform.dist.time").first.tags, "event_type:test_event"
  end

  test "collects base stats on unhandled errors" do
    GitHub.stubs(:dogstats).returns(GitHub::MemoryDogstatsD.new)

    perform_enqueued_jobs do # rubocop:todo GitHub/RequireOnlyWhenCallingPerformEnqueuedJobsInTests
      assert_raises do
        TestFailsPerformJob.perform_later
      end
    end

    assert_includes GitHub.dogstats.increments("active_job.enqueued").first.tags, "class:test_fails_perform_job"
    assert_includes GitHub.dogstats.increments("active_job.performed").first.tags, "class:test_fails_perform_job"
    assert_includes GitHub.dogstats.distributions("active_job.enqueue.dist.time").first.tags, "class:test_fails_perform_job"
    assert_includes GitHub.dogstats.distributions("active_job.perform.dist.time").first.tags, "error:runtime_error"
  end

  test "collects stats on retries" do
    GitHub.stubs(:dogstats).returns(GitHub::MemoryDogstatsD.new)

    perform_enqueued_jobs(only: [TestRetryApplicationJob]) do
      TestRetryApplicationJob.perform_later("Freno::Throttler::Error", 5)
    end

    metrics = GitHub.dogstats.increments("active_job.retry")
    assert_equal 4, metrics.length
    assert_equal Set[
      "catalog_service:github/wall_e",
      "class:test_retry_application_job",
      "queue:default",
      "adapter:aqueduct",
      "error:freno/throttler/error",
      "attempt_number:4" ],
      metrics.first.tags

    assert_includes GitHub.dogstats.increments("active_job.performed").first.tags, "class:test_retry_application_job"
    assert_includes GitHub.dogstats.distributions("active_job.enqueue.dist.time").first.tags, "class:test_retry_application_job"
    refute_includes GitHub.dogstats.distributions("active_job.perform.dist.time").first.tags, "error:freno/throttler/error"

    unless GitHub.enterprise?
      assert_equal "github/wall_e", Failbot.squash_contexts(Failbot.context)["catalog_service"]
      assert_equal "github/wall_e", Audit.context[:catalog_service]
      assert_equal "github/wall_e", GitHub.context[:catalog_service]
    end
  end

  test "collects stats on exhausted retries" do
    GitHub.stubs(:dogstats).returns(GitHub::MemoryDogstatsD.new)

    perform_enqueued_jobs only: TestRetryApplicationJob do
      assert_raises Freno::Throttler::Error do
        TestRetryApplicationJob.perform_later("Freno::Throttler::Error", 11)
      end
    end

    metrics = GitHub.dogstats.increments("active_job.stop_retry")
    assert_equal 1, metrics.length
    assert_equal Set[
      "catalog_service:github/wall_e",
      "class:test_retry_application_job",
      "queue:default",
      "adapter:aqueduct",
      "error:freno/throttler/error" ],
      metrics.first.tags

    assert_equal 1, Failbot.squash_contexts(Failbot.context)["special_failbot_stuff"]

    unless GitHub.enterprise?
      assert_equal "github/wall_e", Failbot.squash_contexts(Failbot.context)["catalog_service"]
      assert_equal "github/wall_e", Audit.context[:catalog_service]
      assert_equal "github/wall_e", GitHub.context[:catalog_service]
    end
  end

  test "sets default logging context" do
    TestSimpleJob.perform_now

    assert_equal "TestSimpleJob", TestSimpleJob.logging_context["gh.job.name"]
    assert_equal "hello", TestSimpleJob.logging_context["gh.stuff"]
    assert TestSimpleJob.logging_context.key?("gh.job.active_job_id")
    assert TestSimpleJob.logging_context.key?("gh.job.aqueduct_id")

    unless GitHub.enterprise?
      assert_equal "github/background_jobs", TestSimpleJob.logging_context["gh.catalog_service"]
    end
  end

  test "sets tenant context logging when enabled and no tenant" do
    GitHub.flipper[:tenant_context_telemetry_background_jobs_splunk].enable

    on_multi_tenant_enterprise do
      TestSimpleJob.perform_now
      assert_equal false, TestSimpleJob.logging_context["gh.tenant_set"]
      assert_equal "enabled", TestSimpleJob.logging_context["gh.tenant.query_scoping"]
    end
  end

  test "sets tenant context logging when enabled and tenant set" do
    GitHub.flipper[:tenant_context_telemetry_background_jobs_splunk].enable

    on_multi_tenant_enterprise do
      mt_business = create(:business)

      TestSimpleJob.any_instance.stubs(:current_tenant).returns(mt_business)
      TestSimpleJob.any_instance.stubs(:unscoped_queries).returns(true)

      TestSimpleJob.perform_now
      assert_equal true, TestSimpleJob.logging_context["gh.tenant_set"]
      assert_equal "enabled", TestSimpleJob.logging_context["gh.tenant.query_scoping"]
      assert_equal mt_business.id, TestSimpleJob.logging_context["gh.tenant.id"]
      assert_equal mt_business.slug, TestSimpleJob.logging_context["gh.tenant.slug"]
    end
  end

  test "retryable errors from overridden failbot_context are retried" do
    GitHub.stubs(:dogstats).returns(GitHub::MemoryDogstatsD.new)


    perform_enqueued_jobs(only: [TestFailbotContextRetryJob]) do
      assert_raises DefaultsError do
        TestFailbotContextRetryJob.perform_later
      end
    end

    metrics = GitHub.dogstats.increments("active_job.retry")
    assert_equal 4, metrics.count { |m| m.tags.include?("error:defaults_error") }
  end

  test "discardable errors from overridden failbot_context are discarded" do
    GitHub.stubs(:dogstats).returns(GitHub::MemoryDogstatsD.new)

    perform_enqueued_jobs(only: [TestFailbotContextDiscardJob]) do
      TestFailbotContextDiscardJob.perform_later
    end

    metrics = GitHub.dogstats.increments("active_job.discard")
    assert_equal 1, metrics.count { |m| m.tags.include?("error:discardable_error") }
  end

  test "successfully retry job when throwing exception against defaults" do
    perform_enqueued_jobs(only: [TestRetryApplicationJob]) do
      TestRetryApplicationJob.perform_later("DefaultsError", 5)
    end

    assert_success_after_attempts("DefaultsError", 5)
  end

  test "successfully retry job on deserialization error" do
    perform_enqueued_jobs(only: [TestRetryDeserializationErrorJob]) do
      TestRetryDeserializationErrorJob.perform_later create(:issue_comment).destroy
    end

    assert_equal ["Raised DeserializationError for the 0th time",
                  "Raised DeserializationError for the 1st time",
                  "Raised DeserializationError for the 2nd time",
                  "Raised DeserializationError for the 3rd time",
                  "Raised DeserializationError for the 4th time",
                  "Failed to execute after 5 attempts"],
                  JobBuffer.values
  end

  context "retry_on_dirty_exit" do
    test "successfully retry job on Aqueduct::Worker::JobKilled error" do
      perform_enqueued_jobs(only: [TestRetryOnDirtyExitApplicationJob]) do
        TestRetryOnDirtyExitApplicationJob.perform_later "Aqueduct::Worker::JobKilled", 5
      end

      assert_success_after_attempts "Aqueduct::Worker::JobKilled", 5
    end

    test "failed retry job when Aqueduct::Worker::JobKilled exception kept occurring beyond defaults" do
      perform_enqueued_jobs do # rubocop:todo GitHub/RequireOnlyWhenCallingPerformEnqueuedJobsInTests
        assert_raises Aqueduct::Worker::JobKilled do
          TestRetryOnDirtyExitApplicationJob.perform_now "Aqueduct::Worker::JobKilled", 6
        end
      end

      assert_failure_after_attempts("Aqueduct::Worker::JobKilled", 5)
    end

    test "failed retry job with custom handling when Aqueduct::Worker::JobKilled exception kept occurring beyond defaults" do
      perform_enqueued_jobs do # rubocop:todo GitHub/RequireOnlyWhenCallingPerformEnqueuedJobsInTests
        TestRetryOnDirtyExitCustomHandlingJob.perform_now "Aqueduct::Worker::JobKilled", 6
      end

      assert_equal "Retrying failed after 5 attempts. Message: Aqueduct::Worker::JobKilled", JobBuffer.values.last
    end

    test "does not retry job when exception is not DirtyExit" do
      perform_enqueued_jobs do # rubocop:todo GitHub/RequireOnlyWhenCallingPerformEnqueuedJobsInTests
        assert_raises StandardError do
          TestRetryOnDirtyExitApplicationJob.perform_now("StandardError", 6)
        end
      end

      assert_failure_after_attempts("StandardError", 1)
    end
  end

  context "retry_on_recoverable_exceptions" do
    test "successfully retry on recoverable exceptions" do
      perform_enqueued_jobs(only: [TestRetryOnRecoverableExceptionsApplicationJob]) do
        attempts = TestRetryOnRecoverableExceptionsApplicationJob::MAX_ATTEMPTS
        TestRetryOnRecoverableExceptionsApplicationJob.perform_later "ActiveRecord::ConnectionNotEstablished", attempts
      end

      assert_success_after_attempts "ActiveRecord::ConnectionNotEstablished", 3
    end

    test "successfully set retry_on attempts" do
      perform_enqueued_jobs(only: [TestRetryOnRecoverableExceptionsApplicationJob]) do
        assert_raises ActiveRecord::ConnectionNotEstablished do
          # Fail often enough to exceed number of attempts configured for this job
          attempts = TestRetryOnRecoverableExceptionsApplicationJob::MAX_ATTEMPTS + 1
          TestRetryOnRecoverableExceptionsApplicationJob.perform_later "ActiveRecord::ConnectionNotEstablished", attempts
        end
      end

      assert_failure_after_attempts("ActiveRecord::ConnectionNotEstablished", 3)
    end

    test "allows custom handling of job when recoverable exceptions exceeds retry attempts" do
      perform_enqueued_jobs(only: [TestRetryOnRecoverableExceptionsCustomHandlingJob]) do
        attempts = TestRetryOnRecoverableExceptionsCustomHandlingJob::MAX_ATTEMPTS + 1
        TestRetryOnRecoverableExceptionsCustomHandlingJob.perform_later "ActiveRecord::ConnectionNotEstablished", attempts
      end
      assert_equal "Dealt with a job that failed to retry in a custom way after 3 attempts. Message: ActiveRecord::ConnectionNotEstablished", JobBuffer.values.last
    end

    test "does not retry when exception is not in Resiliency::Response::UnavailableExceptions" do
      perform_enqueued_jobs do # rubocop:todo GitHub/RequireOnlyWhenCallingPerformEnqueuedJobsInTests
        assert_raises StandardError do
          TestRetryOnRecoverableExceptionsApplicationJob.perform_now "StandardError", 2
        end
      end

      assert_failure_after_attempts("StandardError", 1)
    end
  end

  test "successfully retry job throwing against higher limit" do
    perform_enqueued_jobs(only: [TestRetryApplicationJob]) do
      TestRetryApplicationJob.perform_later("ShortWaitTenAttemptsError", 9)
    end

    assert_success_after_attempts("ShortWaitTenAttemptsError", 9)
  end

  test "failed retry job when exception kept occurring against defaults" do
    perform_enqueued_jobs do # rubocop:todo GitHub/RequireOnlyWhenCallingPerformEnqueuedJobsInTests
      assert_raises DefaultsError do
        TestRetryApplicationJob.perform_now("DefaultsError", 6)
      end
    end

    assert_failure_after_attempts("DefaultsError", 5)
  end

  test "failed retry job when exception kept occurring against higher limit" do
    perform_enqueued_jobs do # rubocop:todo GitHub/RequireOnlyWhenCallingPerformEnqueuedJobsInTests
      assert_raises ShortWaitTenAttemptsError do
        TestRetryApplicationJob.perform_now("ShortWaitTenAttemptsError", 11)
      end
    end

    assert_failure_after_attempts("ShortWaitTenAttemptsError", 10)
  end

  test "discard job" do
    perform_enqueued_jobs(only: [TestRetryApplicationJob]) do
      TestRetryApplicationJob.perform_later("DiscardableError", 2)
    end

    assert_failure_after_attempts("DiscardableError", 1)
  end

  test "custom handling of discarded job" do
    perform_enqueued_jobs(only: [TestRetryApplicationJob]) do
      TestRetryApplicationJob.perform_later("CustomDiscardableError", 2)
    end

    assert_equal "Dealt with a job that was discarded in a custom way. Message: CustomDiscardableError", JobBuffer.values.last
  end

  test "custom handling of job that exceeds retry attempts" do
    perform_enqueued_jobs(only: [TestRetryApplicationJob]) do
      TestRetryApplicationJob.perform_later("CustomCatchError", 6)
    end

    assert_equal "Dealt with a job that failed to retry in a custom way after 6 attempts. Message: CustomCatchError", JobBuffer.values.last
  end

  test "long wait job" do
    travel_to Time.now

    perform_enqueued_jobs(only: [TestRetryApplicationJob]) do
      assert_performed_with at: (Time.now + 3600.seconds) do
        TestRetryApplicationJob.perform_later("LongWaitError", 5)
      end
    end
  end

  test "exponentially retrying job" do
    travel_to Time.now

    perform_enqueued_jobs(only: [TestRetryApplicationJob]) do
      assert_performed_with at: (Time.now + 3.seconds) do
        assert_performed_with at: (Time.now + 18.seconds) do
          assert_performed_with at: (Time.now + 83.seconds) do
            assert_performed_with at: (Time.now + 258.seconds) do
              TestRetryApplicationJob.perform_later "ExponentialWaitTenAttemptsError", 5
            end
          end
        end
      end
    end
  end

  test "increments execution counter on jobs that don't have it" do
    perform_enqueued_jobs(only: [TestNoCounterApplicationJob]) do
      TestNoCounterApplicationJob.perform_later
    end

    assert_success_after_attempts(nil, 1)
  end

  test "retries on any Freno::Throttler::Error" do
    perform_enqueued_jobs(only: [TestRetryApplicationJob]) do
      TestRetryApplicationJob.perform_later("Freno::Throttler::Error", 2)
    end

    assert_success_after_attempts("Freno::Throttler::Error", 2)
  end

  test "subclass rescue_from pre-empts base rescue_froms/retries" do
    TestRetryWithRescueFromJob.perform_now "Freno::Throttler::Error", 2

    # job is not retried (no "Successfully completed job" in buffer)
    # because the throttler error is first caught by the subclass's rescue_from
    assert_equal [
      "Raised Freno::Throttler::Error for the 1st time",
      "Rescued from StandardError in subclass",
    ], JobBuffer.values
  end

  test "perform exceptions are instrumented" do
    events = subscribe "error.active_job"

    assert_raises { TestFailsPerformJob.perform_now }

    assert_equal 1, events.length
    assert_equal "perform failed", events.first.payload[:error].message
    assert_kind_of TestFailsPerformJob, events.first.payload[:job]
  end

  test "enqueue exceptions are instrumented" do
    events = subscribe "error.active_job"

    perform_enqueued_jobs do # rubocop:todo GitHub/RequireOnlyWhenCallingPerformEnqueuedJobsInTests
      assert_raises do
        TestFailsEnqueueJob.perform_later
      end
    end

    assert_equal 1, events.length
    assert_equal "enqueue failed", events.first.payload[:error].message
    assert_kind_of TestFailsEnqueueJob, events.first.payload[:job]
  end

  test "exceptions are recorded to dogstats" do
    GitHub.stubs(:dogstats).returns(GitHub::MemoryDogstatsD.new)

    assert_raises { TestFailsPerformJob.perform_now }
    refute_empty GitHub.dogstats.increments("active_job.error", tags: [
      "class:test_fails_perform_job",
      "queue:default",
      "adapter:aqueduct",
      "error:runtime_error",
      "on:perform",
    ])
  end

  test "retriable exceptions do not instrument errors" do
    GitHub.stubs(:dogstats).returns(GitHub::MemoryDogstatsD.new)

    TestRetryBasedOnCauseJob.perform_now
    assert_empty GitHub.dogstats.increments("active_job.error", tags: [
      "class:test_retry_based_on_cause_job",
      "queue:default",
      "adapter:aqueduct",
      "on:perform",
    ])
  end

  test "retry exhaustion instruments errors" do
    GitHub.stubs(:dogstats).returns(GitHub::MemoryDogstatsD.new)

    job = TestRetryApplicationJob.new("DefaultsError", 10)
    assert_raises { 5.times { job.perform_now } }
    refute_empty GitHub.dogstats.increments("active_job.error", tags: [
      "class:test_retry_application_job",
      "queue:default",
      "adapter:aqueduct",
      "error:defaults_error",
      "on:perform",
    ])
  end

  test "enqueue exceptions are recorded to dogstats" do
    GitHub.stubs(:dogstats).returns(GitHub::MemoryDogstatsD.new)

    perform_enqueued_jobs do # rubocop:todo GitHub/RequireOnlyWhenCallingPerformEnqueuedJobsInTests
      assert_raises do
        TestFailsEnqueueJob.perform_later
      end
    end

    refute_empty GitHub.dogstats.increments("active_job.error", tags: [
      "class:test_fails_enqueue_job",
      "queue:default",
      "adapter:aqueduct",
      "error:runtime_error",
      "on:enqueue",
    ])

    refute_empty GitHub.dogstats.increments("active_job.enqueue_error", tags: [
      "class:test_fails_enqueue_job",
      "queue:default",
      "adapter:aqueduct",
      "error:runtime_error",
    ])
  end

  test "original errors (wrapped by DeserializationError) can be rescued directly" do
    perform_enqueued_jobs(only: [TestRecordNotFoundJob]) do
      TestRecordNotFoundJob.perform_later create(:issue_comment).destroy
    end

    assert_equal ["Discarded after AR NotFound"], JobBuffer.values
  end

  context "when skip_enqueue feature flag is set for a job" do
    test "the job is not enqueued" do
      GitHub.flipper[:active_job_skip_enqueue].enable(TestSimpleJob.job_class_actor)
      TestSimpleJob.perform_later
      assert_enqueued_jobs 0
    end

    test "increments a counter" do
      GitHub.stubs(:dogstats).returns(GitHub::MemoryDogstatsD.new)
      GitHub.flipper[:active_job_skip_enqueue].enable(TestSimpleJob.job_class_actor)
      TestSimpleJob.perform_later

      metric = GitHub.dogstats.increments("active_job.enqueue_skipped").first
      assert metric
      assert_includes metric.tags, "class:test_simple_job"
      assert_includes metric.tags, "queue:default"
      assert_includes metric.tags, "adapter:aqueduct"
    end
  end

  context "enqueue_once_per_interval" do
    test "enqueues only one job per interval" do
      GitHub.stubs(:dogstats).returns(GitHub::MemoryDogstatsD.new)
      # A time that ensures this test spans two minute intervals.
      enqueue_time = Time.local(2022, 6, 23, 11, 59, 30)
      interval = 60

      (1..5).each do |id|
        Timecop.freeze(enqueue_time + id.seconds) do
          TestSimpleParameterizedJob.enqueue_once_per_interval(args: [id], interval: interval, unique_id: "unique_id")
        end
      end

      assert_equal 1, enqueued_jobs.size
      assert_equal({ job: TestSimpleParameterizedJob, args: [1] }, enqueued_jobs[0].slice(:job, :args))
      # Ensure that the first job is scheduled for enqueued_at + interval.
      assert_equal enqueued_jobs[0]["enqueued_at"].to_time + interval.seconds, Time.at(enqueued_jobs[0][:at])
      assert_equal 1, GitHub.dogstats.increments("job.once_per_interval.queued", tags: ["class:#{TestSimpleParameterizedJob.name.underscore}"]).count
      assert_equal 4, GitHub.dogstats.increments("job.once_per_interval.duplicate", tags: ["class:#{TestSimpleParameterizedJob.name.underscore}"]).count

      perform_enqueued_jobs only: TestSimpleParameterizedJob
      assert_equal 0, enqueued_jobs.size, "queue should be clear"
      reset_redis # Clear out locks

      TestSimpleParameterizedJob.enqueue_once_per_interval(args: [11], interval: 60, unique_id: "unique_id")
      assert_equal 1, enqueued_jobs.size
      assert_equal 2, GitHub.dogstats.increments("job.once_per_interval.queued", tags: ["class:#{TestSimpleParameterizedJob.name.underscore}"]).count
    end

    test "performs job at the beginning of the interval when 'start: true'" do
      GitHub.stubs(:dogstats).returns(GitHub::MemoryDogstatsD.new)
      # A time that ensures this test spans two minute intervals.
      enqueue_time = Time.local(2022, 6, 23, 11, 59, 30)
      interval = 60

      Timecop.freeze(enqueue_time + 1.second) do
        TestSimpleParameterizedJob.enqueue_once_per_interval(args: [1], interval: interval, run_at_beginning_of_interval: true, unique_id: "unique_id")
        assert_equal 1, enqueued_jobs.size
        assert_nil enqueued_jobs[0][:at]
      end

      Timecop.freeze(enqueue_time + 2.seconds) do
        perform_enqueued_jobs(only: TestSimpleParameterizedJob, at: Time.now)
        assert_equal 0, enqueued_jobs.size, "retry queue should be clear"

        TestSimpleParameterizedJob.enqueue_once_per_interval(args: [11], interval: 60, run_at_beginning_of_interval: true, unique_id: "unique_id")
        assert_equal 0, enqueued_jobs.size
      end
    end

    test "reports unable to lock error to datadog" do
      GitHub.stubs(:dogstats).returns(GitHub::MemoryDogstatsD.new)

      perform_enqueued_jobs(only: [TestRescueUnableToLock]) do
        TestRescueUnableToLock.perform_later
      end

      attempts = JobBuffer.values.count { |v| v == "Raised GitHub::Restraint::UnableToLock" }
      assert_equal TestRescueUnableToLock::ATTEMPTS, attempts

      metric = GitHub.dogstats.increments("active_job.unable_to_lock").first
      assert_equal 1, metric.value
      assert_includes metric.tags, "class:test_rescue_unable_to_lock"
      assert_includes metric.tags, "catalog_service:github/unknown" unless GitHub.enterprise?
    end

    test "additional tags are added to datadog metrics" do
      GitHub.stubs(:dogstats).returns(GitHub::MemoryDogstatsD.new)
      # A time that ensures this test spans two minute intervals.
      enqueue_time = Time.local(2022, 6, 23, 11, 59, 30)
      interval = 60

      (1..5).each do |id|
        Timecop.freeze(enqueue_time + id.seconds) do
          TestSimpleParameterizedJob.enqueue_once_per_interval(args: [id], interval: interval, unique_id: "unique_id", additional_tags: ["foo:bar"])
        end
      end

      assert_equal 1, enqueued_jobs.size

      queued_metric = GitHub.dogstats.increments("job.once_per_interval.queued")
      assert_equal 1, queued_metric.count
      assert_includes queued_metric.first.tags, "class:#{TestSimpleParameterizedJob.name.underscore}"
      assert_includes queued_metric.first.tags, "foo:bar"

      duplicate_metric = GitHub.dogstats.increments("job.once_per_interval.duplicate")
      assert_equal 4, duplicate_metric.count
      assert_includes duplicate_metric.first.tags, "class:#{TestSimpleParameterizedJob.name.underscore}"
      assert_includes queued_metric.first.tags, "foo:bar"
    end

    test "same class and job args only enqueue once" do
      TestSimpleParameterizedJob.enqueue_once_per_interval(args: ["args"], interval: 30)
      TestSimpleParameterizedJob.enqueue_once_per_interval(args: ["args"], interval: 30)
      assert_equal 1, enqueued_jobs.count, "only one job should have been queued"
    end

    test "same class and different job args enqueue once each" do
      TestSimpleParameterizedJob.enqueue_once_per_interval(args: ["args"], interval: 30)
      TestSimpleParameterizedJob.enqueue_once_per_interval(args: ["args2"], interval: 30)
      assert_equal 2, enqueued_jobs.count, "both jobs should have been queued"
    end

    test "different class and same job args enqueue once each" do
      TestSimpleParameterizedJob.enqueue_once_per_interval(args: ["args"], interval: 30)
      TestSimpleParameterizedTwoJob.enqueue_once_per_interval(args: ["args"], interval: 30)
      assert_equal 2, enqueued_jobs.count, "both jobs should have been queued"
    end

    test "same class and args but different interval enqueue once each" do
      TestSimpleParameterizedJob.enqueue_once_per_interval(args: ["args"], interval: 30)
      TestSimpleParameterizedJob.enqueue_once_per_interval(args: ["args"], interval: 60)
      assert_equal 2, enqueued_jobs.count, "both jobs should have been queued"
    end

    test "same class and different args enqueue once when same unique id is specified" do
      TestSimpleParameterizedJob.enqueue_once_per_interval(args: ["args"], interval: 60, unique_id: "unique_id")
      TestSimpleParameterizedJob.enqueue_once_per_interval(args: ["args2"], interval: 60, unique_id: "unique_id")
      assert_equal 1, enqueued_jobs.count, "only one job should have been queued"
    end

    test "same class and same unique id enqueue once each when different interval specified" do
      TestSimpleParameterizedJob.enqueue_once_per_interval(args: ["args"], interval: 30, unique_id: "unique_id")
      TestSimpleParameterizedJob.enqueue_once_per_interval(args: ["args"], interval: 60, unique_id: "unique_id")
      assert_equal 2, enqueued_jobs.count, "both jobs should have been queued"
    end

    test "specifying an interval of 0 enqueues the job immediately" do
      freeze_time do
        TestSimpleParameterizedJob.enqueue_once_per_interval(args: ["args"], interval: 0)
        TestSimpleParameterizedJob.enqueue_once_per_interval(args: ["args"], interval: 0)
      end
      assert_equal 2, enqueued_jobs.count, "job should have been queued"
    end

    test "using hash args when unique id is not specified" do
      TestSimpleParameterizedJob.enqueue_once_per_interval(kwargs: { id: 123 }, interval: 60)
      TestSimpleParameterizedJob.enqueue_once_per_interval(kwargs: { id: 123 }, interval: 60)
      assert_equal 1, enqueued_jobs.count, "only one job should have been queued"
    end
  end

  test "sets package context" do
    GitHub.packageowners.stubs(:package_for_type).returns("test-package")
    assert_nothing_raised do
      PackageContextTestJob.perform_now
    end
  end

  test "sets gh context only during job performance" do
    GH::Context.__reset
    assert_equal GH.context, GH::Context::NULL_CONTEXT
    GHContextTestJob.perform_now
    assert_equal GH.context, GH::Context::NULL_CONTEXT
  end

  def assert_success_after_attempts(error, attempts)
    assert_equal (attempts - 1).times.with_index(1)
      .map { |*, attempt| "Raised #{error} for the #{attempt.ordinalize} time" }
      .push("Successfully completed job"),
      JobBuffer.values
  end

  def assert_failure_after_attempts(error, attempts)
    assert_equal attempts.times.with_index(1)
      .map { |*, attempt| "Raised #{error} for the #{attempt.ordinalize} time" },
      JobBuffer.values
  end
end
