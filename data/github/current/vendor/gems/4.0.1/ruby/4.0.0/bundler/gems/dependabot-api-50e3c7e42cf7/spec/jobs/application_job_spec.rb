# frozen_string_literal: true

require "rails_helper"

RSpec.describe ApplicationJob, type: :job do
  include ActiveJob::TestHelper
  include LoggingHelpers

  before do
    Failbot.reset!
    Failbot.setup(
      { "FAILBOT_BACKEND" => "memory" }, { "shared" => "Default Context" }
    )
    Failbot.clear_before_report
  end

  describe "#perform_now" do
    context "with a job" do
      before do
        dummy_class = Class.new(described_class) do
          def perform
            raise unless ::Dependabot::Exceptions.context.first[:transaction] == "DummyJob"
          end
        end
        stub_const("DummyJob", dummy_class)
      end

      it "sets up the exception context" do
        ::Dependabot::Exceptions.reset!
        ::Dependabot::Exceptions.push({ "gh.repo.id": 123 })

        DummyJob.new.perform_now
        expect(::Dependabot::Exceptions.context).to eq([])
      end
    end

    context "with a job that logs" do
      before do
        dummy_class = Class.new(described_class) do
          def perform
            Dependabot::Logger.info(msg: "Hello, World!")
          end
        end
        stub_const("DummyJob", dummy_class)
      end

      it "includes the job log_context in the log output" do
        log_output = StringIO.new
        Scrolls.stream = log_output

        job = DummyJob.new
        job.perform_now

        expect(structured_log_values(log_output.string)).to include(
          "app=dependabot-api", "env=test", "gh.aqueduct.job.id=#{job.job_id}",
          "gh.aqueduct.queue.name=default", "messaging.active_job.retry=false",
          "messaging.active_job.executions=0", "msg=\"Hello, World!\"",
          "level=info",
        )
      end
    end

    context "with a job that raises an exception" do
      before do
        dummy_error_class = Class.new(described_class) do
          def perform
            raise "Some error"
          end
        end
        stub_const("DummyErrorJob", dummy_error_class)
      end

      it "reports exceptions but doesn't swallow them" do
        expect do
          DummyErrorJob.new.perform_now
        end.to raise_error(RuntimeError, "Some error")

        expect(Failbot.reports).not_to be_empty
        expect(Failbot.reports.length).to be(1)
        event = Failbot.reports.last
        expect(event["exception_detail"].last["value"]).to eq("Some error")
        expect(event["transaction"]).to eq("DummyErrorJob")
        expect(MetricsClient).to have_received(:increment).
          with("job.failed",
               tags: {
                 job: "dummy_error_job",
                 error: "runtime_error",
                 "queue": "default",
               })
      end

      # rubocop:disable RSpec/ExampleLength
      it "reports exceptions when enqueued with perform_later" do
        expect do
          DummyErrorJob.perform_later
          perform_enqueued_jobs
        end.to raise_error(RuntimeError, "Some error")

        expect(Failbot.reports).not_to be_empty
        expect(Failbot.reports.length).to be(1)
        event = Failbot.reports.last
        expect(event["exception_detail"].last["value"]).to eq("Some error")
        expect(event["transaction"]).to eq("DummyErrorJob")
        expect(MetricsClient).to have_received(:increment).
          with("job.enqueued",
               tags: {
                 job: "dummy_error_job",
                 queue: "default",
                 retry: false,
               })
        expect(MetricsClient).to have_received(:increment).
          with("job.failed",
               tags: {
                 job: "dummy_error_job",
                 error: "runtime_error",
                 "queue": "default",
               })
      end
      # rubocop:enable RSpec/ExampleLength

      it "includes additional context about the job in the report" do
        expect do
          DummyErrorJob.new.perform_now
        end.to raise_error(RuntimeError, "Some error")

        expect(Failbot.reports).not_to be_empty
        expect(Failbot.reports.length).to be(1)
        event = Failbot.reports.last
        expect(event["transaction"]).to eq("DummyErrorJob")
        expect(event["messaging.active_job.retry"]).to eq("false")
        expect(event["messaging.active_job.executions"]).to eq(0)
        expect(event["gh.aqueduct.queue.name"]).to eq("default")
        expect(event["#gh.aqueduct.job.id"]).not_to be_empty
        expect(event["rollup"]).to eq(Digest::MD5.hexdigest("RuntimeErrorDummyErrorJob"))
      end

      it "logs the error using Dependabot::Logger and includes the job log_context" do
        log_output = StringIO.new
        Scrolls.stream = log_output

        job = DummyErrorJob.new

        expect do
          job.perform_now
        end.to raise_error(RuntimeError, "Some error")

        expect(structured_log_values(log_output.string)).to include(
          "app=dependabot-api", "env=test", "gh.aqueduct.job.id=#{job.job_id}",
          "gh.aqueduct.queue.name=default", "messaging.active_job.retry=false",
          "messaging.active_job.executions=0", "msg=\"DummyErrorJob encountered an error\"",
          "code.namespace=DummyErrorJob", "exception.message=\"Some error\"",
          "exception.type=RuntimeError", "level=warning"
        )
      end
    end

    # rubocop:disable RSpec/ExampleLength
    context "with a job that raises an exception but configures retries" do
      before do
        dummy_retry_class = Class.new(described_class) do
          retry_on StandardError, attempts: 2
          def perform
            raise StandardError, "Some error"
          end
        end
        stub_const("DummyRetryJob", dummy_retry_class)
      end

      it "doesn't report retryable errors until retries are exhausted" do
        job = DummyRetryJob.new

        # First attempt
        job.perform_now

        expect(Failbot.reports).to be_empty
        expect(MetricsClient).to have_received(:increment).
          with("job.retry_scheduled",
               tags: {
                 job: "dummy_retry_job",
                 error: "standard_error",
                 "queue": "default",
               })
        expect(MetricsClient).to have_received(:timing).
          with("job.time",
               anything,
               tags: {
                 job: "dummy_retry_job",
                 retry: false,
                 "queue": "default",
               })

        # Retry attempt
        expect do
          job.perform_now
        end.to raise_error(StandardError, "Some error")

        expect(Failbot.reports).not_to be_empty
        expect(Failbot.reports.length).to be(1)
        event = Failbot.reports.last
        expect(event["exception_detail"].last["value"]).to eq("Some error")
        expect(event["messaging.active_job.retry"]).to eq("true")
        expect(event["messaging.active_job.executions"]).to eq(1)
        expect(MetricsClient).to have_received(:increment).
          with("job.retry_stopped",
               tags: {
                 job: "dummy_retry_job",
                 error: "standard_error",
                 "queue": "default",
               })
        expect(MetricsClient).to have_received(:timing).
          with("job.time",
               anything,
               tags: {
                 job: "dummy_retry_job",
                 retry: true,
                 "queue": "default",
               })
        expect(MetricsClient).to have_received(:increment).
          with("job.failed",
               tags: {
                 job: "dummy_retry_job",
                 error: "standard_error",
                 "queue": "default",
               }).once
      end

      it "indicates the retry on enqueue metrics" do
        # First attempt
        DummyRetryJob.perform_later
        expect(MetricsClient).to have_received(:increment).
          with("job.enqueued",
               tags: {
                 job: "dummy_retry_job",
                 queue: "default",
                 retry: false,
               })

        perform_enqueued_jobs

        expect(MetricsClient).to have_received(:increment).
          with("job.scheduled",
               tags: {
                 job: "dummy_retry_job",
                 queue: "default",
                 retry: true,
               })
      end
    end
    # rubocop:enable RSpec/ExampleLength

    # rubocop:disable RSpec/ExampleLength
    context "with a job that raises an exception but configures retries via ActiveJob::Retry" do
      before do
        dummy_retry_class = Class.new(described_class) do
          include ActiveJob::Retry.new(
            strategy: RateLimitBackoffStrategy.new(
              limit: 2,
              retryable_exceptions: [
                StandardError,
              ],
            ),
          )
          def perform
            raise StandardError, "Some error"
          end
        end
        stub_const("DummyRetryJob", dummy_retry_class)
      end

      it "doesn't report retryable errors until retries are exhausted" do
        job = DummyRetryJob.new

        # First attempt
        job.perform_now

        expect(Failbot.reports).to be_empty
        expect(MetricsClient).to have_received(:increment).
          with("job.retry_scheduled",
               tags: {
                 job: "dummy_retry_job",
                 error: "none", # ActiveJob::Retry doesn't set the error
                 "queue": "default",
               })
        expect(MetricsClient).to have_received(:timing).
          with("job.time",
               anything,
               tags: {
                 job: "dummy_retry_job",
                 retry: false,
                 "queue": "default",
               })

        # Retry attempt
        expect do
          job.perform_now
        end.to raise_error(StandardError, "Some error")

        expect(Failbot.reports).not_to be_empty
        expect(Failbot.reports.length).to be(1)
        event = Failbot.reports.last
        expect(event["exception_detail"].last["value"]).to eq("Some error")
        expect(MetricsClient).not_to have_received(:increment).
          with("job.retry_stopped", # ActiveJob::Retry doesn't report this
               anything)
        expect(MetricsClient).to have_received(:timing).
          with("job.time",
               anything,
               tags: {
                 job: "dummy_retry_job",
                 retry: true,
                 "queue": "default",
               })
        expect(MetricsClient).to have_received(:increment).
          with("job.failed",
               tags: {
                 job: "dummy_retry_job",
                 error: "standard_error",
                 "queue": "default",
               }).once
      end
      # rubocop:enable RSpec/ExampleLength
    end

    context "with a job that raises an exception but configures discards" do
      before do
        dummy_discard_class = Class.new(described_class) do
          discard_on StandardError
          def perform
            raise StandardError, "Some error"
          end
        end
        stub_const("DummyDiscardJob", dummy_discard_class)
      end

      it "doesn't report discarded errors" do
        DummyDiscardJob.new.perform_now

        expect(Failbot.reports).to be_empty
        expect(MetricsClient).to have_received(:increment).
          with("job.discarded",
               tags: {
                 job: "dummy_discard_job",
                 error: "standard_error",
                 "queue": "default",
               })
        expect(MetricsClient).not_to have_received(:increment).
          with("job.failed",
               anything)
      end
    end

    context "with a job that raises a discarded exception as a cause" do
      before do
        dummy_discard_class = Class.new(described_class) do
          discard_on StandardError
          def perform
            raise StandardError, "Some error"
          rescue StandardError
            raise RuntimeError
          end
        end
        stub_const("DummyDiscardJob", dummy_discard_class)
      end

      it "doesn't report the error with the discarded cause" do
        DummyDiscardJob.new.perform_now

        expect(Failbot.reports).to be_empty
        expect(MetricsClient).to have_received(:increment).
          with("job.discarded",
               tags: {
                 job: "dummy_discard_job",
                 error: "runtime_error",
                 "queue": "default",
               })
        expect(MetricsClient).not_to have_received(:increment).
          with("job.failed",
               anything)
      end
    end
  end

  describe "#retry_on_dirty_exit" do
    let(:dummy_job_class) do
      Class.new(described_class) do
        retry_on_dirty_exit

        def perform(error_class)
          raise error_class.constantize
        end
      end
    end

    before do
      stub_const("DummyJob", dummy_job_class)
    end

    it "allows 5 attempts when it fails with JobKilled" do
      DummyJob.perform_later("Aqueduct::Worker::JobKilled")
      4.times { perform_enqueued_jobs }
      expect do
        perform_enqueued_jobs
      end.to raise_error(Aqueduct::Worker::JobKilled)
    end

    it "doesn't retry for other errors" do
      DummyJob.perform_later("StandardError")
      expect do
        perform_enqueued_jobs
      end.to raise_error(StandardError)
    end

    context "with a handler" do
      let(:dummy_job_class) do
        Class.new(described_class) do
          class << self
            attr_accessor :handled
          end

          retry_on_dirty_exit do
            self.handled ||= 0
            self.handled += 1
          end

          def perform(error_class)
            raise error_class.constantize
          end
        end
      end

      it "runs the handler" do
        expect(DummyJob.handled).to be_nil
        perform_enqueued_jobs do
          expect { DummyJob.perform_now("Aqueduct::Worker::JobKilled") }.not_to raise_error
        end
        expect(DummyJob.handled).to eq(1)
      end
    end
  end

  describe "#retry_on_recoverable_aqueduct_exceptions" do
    let(:dummy_job_class) do
      Class.new(described_class) do
        retry_on_recoverable_aqueduct_exceptions

        def perform(error_class)
          raise error_class.constantize
        end
      end
    end

    before do
      stub_const("DummyJob", dummy_job_class)
    end

    it "allows 5 attempts when it fails with a recoverable error" do
      DummyJob.perform_later("Aqueduct::Client::ClientError")
      4.times { perform_enqueued_jobs }
      expect do
        perform_enqueued_jobs
      end.to raise_error(Aqueduct::Client::ClientError)
    end

    it "doesn't retry for other errors" do
      DummyJob.perform_later("Aqueduct::Worker::JobKilled")
      expect do
        perform_enqueued_jobs
      end.to raise_error(Aqueduct::Worker::JobKilled)
    end

    context "with a handler" do
      let(:dummy_job_class) do
        Class.new(described_class) do
          class << self
            attr_accessor :handled
          end

          retry_on_recoverable_aqueduct_exceptions do
            self.handled ||= 0
            self.handled += 1
          end

          def perform(error_class)
            raise error_class.constantize
          end
        end
      end

      it "runs the handler" do
        expect(DummyJob.handled).to be_nil
        perform_enqueued_jobs do
          expect { DummyJob.perform_now("Aqueduct::Client::ClientError") }.not_to raise_error
        end
        expect(DummyJob.handled).to eq(1)
      end
    end
  end

  describe "#retry_on_recoverable_database_exceptions" do
    let(:dummy_job_class) do
      Class.new(described_class) do
        retry_on_recoverable_database_exceptions

        def perform(error_class)
          raise error_class.constantize
        end
      end
    end

    before do
      stub_const("DummyJob", dummy_job_class)
    end

    it "allows 5 attempts when it fails with a recoverable error" do
      DummyJob.perform_later("Trilogy::ConnectionRefusedError")
      4.times { perform_enqueued_jobs }
      expect do
        perform_enqueued_jobs
      end.to raise_error(Trilogy::ConnectionRefusedError)
    end

    it "doesn't retry for other errors" do
      DummyJob.perform_later("Aqueduct::Worker::JobKilled")
      expect do
        perform_enqueued_jobs
      end.to raise_error(Aqueduct::Worker::JobKilled)
    end

    context "with a handler" do
      let(:dummy_job_class) do
        Class.new(described_class) do
          class << self
            attr_accessor :handled
          end

          retry_on_recoverable_database_exceptions do
            self.handled ||= 0
            self.handled += 1
          end

          def perform(error_class)
            raise error_class.constantize
          end
        end
      end

      it "runs the handler" do
        expect(DummyJob.handled).to be_nil
        perform_enqueued_jobs do
          expect { DummyJob.perform_now("Trilogy::ConnectionRefusedError") }.not_to raise_error
        end
        expect(DummyJob.handled).to eq(1)
      end
    end
  end

  describe "#retry_on_restraint_unable_to_lock" do
    let(:dummy_job_class) do
      Class.new(described_class) do
        # retry 5 times
        retry_on_restraint_unable_to_lock(wait: 1.second, job_retry_ttl: 5.seconds)

        def perform(error_class)
          raise error_class.constantize
        end
      end
    end

    before do
      stub_const("DummyJob", dummy_job_class)
    end

    it "retries for a set period of time when it fails with Restraint::UnableToLock" do
      DummyJob.perform_later("Restraint::UnableToLock")
      # exhaust retries
      4.times { perform_enqueued_jobs }

      expect do
        perform_enqueued_jobs
      end.to raise_error(Restraint::UnableToLock)
    end

    it "increments a job metric" do
      DummyJob.perform_later("Restraint::UnableToLock")
      expect do
        5.times { perform_enqueued_jobs }
      end.to raise_error(Restraint::UnableToLock)

      expect(MetricsClient).to have_received(:increment).with(
        "job.unable_to_lock_restraint",
        tags: { job: "dummy_job", queue: "default" }
      ).exactly(5).times
    end

    it "doesn't retry for other errors" do
      DummyJob.perform_later("Aqueduct::Worker::JobKilled")
      expect do
        perform_enqueued_jobs
      end.to raise_error(Aqueduct::Worker::JobKilled)
    end

    context "with a handler" do
      let(:dummy_job_class) do
        Class.new(described_class) do
          class << self
            attr_accessor :handled
          end

          retry_on_restraint_unable_to_lock(wait: 1.second, job_retry_ttl: 5.seconds) do
            self.handled ||= 0
            self.handled += 1
          end

          def perform(error_class)
            raise error_class.constantize
          end
        end
      end

      it "runs the handler" do
        expect(DummyJob.handled).to be_nil
        perform_enqueued_jobs do
          expect { DummyJob.perform_now("Restraint::UnableToLock") }.not_to raise_error
        end
        expect(DummyJob.handled).to eq(1)
      end
    end
  end

  describe "#retry_on_throttler_timeout" do
    let(:dummy_job_class) do
      Class.new(described_class) do
        retry_on_throttler_timeout(wait: 1.second, job_retry_ttl: 5.seconds)

        def perform(error_class)
          raise error_class.constantize
        end
      end
    end

    before do
      stub_const("DummyJob", dummy_job_class)
    end

    it "retries for a set period of time when it fails with Throttler::TimeoutError" do
      DummyJob.perform_later("Throttler::TimeoutError")
      # exhaust retries
      4.times { perform_enqueued_jobs }

      expect do
        perform_enqueued_jobs
      end.to raise_error(Throttler::TimeoutError)
    end

    it "doesn't retry for other errors" do
      DummyJob.perform_later("Aqueduct::Worker::JobKilled")
      expect do
        perform_enqueued_jobs
      end.to raise_error(Aqueduct::Worker::JobKilled)
    end

    context "with a handler" do
      let(:dummy_job_class) do
        Class.new(described_class) do
          class << self
            attr_accessor :handled
          end

          retry_on_throttler_timeout(wait: 1.second, job_retry_ttl: 5.seconds) do
            self.handled ||= 0
            self.handled += 1
          end

          def perform(error_class)
            raise error_class.constantize
          end
        end
      end

      it "runs the handler" do
        expect(DummyJob.handled).to be_nil
        perform_enqueued_jobs do
          expect { DummyJob.perform_now("Throttler::TimeoutError") }.not_to raise_error
        end
        expect(DummyJob.handled).to eq(1)
      end
    end
  end

  describe "#default_retries_for_idempotent_jobs" do
    let(:dummy_job_class) do
      Class.new(described_class) do
        default_retries_for_idempotent_jobs

        def perform(error_class)
          raise error_class.constantize
        end
      end
    end

    before do
      stub_const("DummyJob", dummy_job_class)
    end

    it "allows 5 attempts when it fails with a recoverable error" do
      recoverable_errors = [
        ActiveRecord::StatementInvalid,
        Aqueduct::Client::ClientError,
        Aqueduct::Worker::JobKilled,
        Trilogy::ConnectionRefusedError,
        Redis::CannotConnectError,
      ]

      recoverable_errors.each do |error|
        DummyJob.perform_later(error.name)
        4.times { perform_enqueued_jobs }
        expect do
          perform_enqueued_jobs
        end.to raise_error(error)
      end
    end

    it "doesn't retry for other errors" do
      DummyJob.perform_later("StandardError")
      expect do
        perform_enqueued_jobs
      end.to raise_error(StandardError)
    end

    context "with a handler" do
      let(:dummy_job_class) do
        Class.new(described_class) do
          class << self
            attr_accessor :handled
          end

          default_retries_for_idempotent_jobs do
            self.handled ||= 0
            self.handled += 1
          end

          def perform(error_class)
            raise error_class.constantize
          end
        end
      end

      it "runs the handler" do
        recoverable_errors = [
          ActiveRecord::StatementInvalid,
          Aqueduct::Client::ClientError,
          Aqueduct::Worker::JobKilled,
          Trilogy::ConnectionRefusedError,
          Redis::CannotConnectError,
        ]

        expect(DummyJob.handled).to be_nil
        recoverable_errors.each_with_index do |error, index|
          perform_enqueued_jobs do
            expect { DummyJob.perform_now(error.name) }.not_to raise_error
          end

          expect(DummyJob.handled).to eq(index + 1)
        end
      end
    end
  end
end
