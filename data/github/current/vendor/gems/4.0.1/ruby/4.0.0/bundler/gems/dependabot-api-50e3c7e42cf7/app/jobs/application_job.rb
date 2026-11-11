# frozen_string_literal: true

require "metrics_active_job"

class ApplicationJob < ActiveJob::Base
  def perform_now(*args)
    ::Dependabot::Exceptions.reset!
    ::Dependabot::Exceptions.push(exception_context) do
      Dependabot::Logger.log_context(log_context) do
        super
      rescue Exception => e # rubocop:disable Lint/RescueException
        # We'll only receive exceptions here if they're not handled by a retry or
        # discard handler.
        instrument_error(e)
        raise
      end
    end
  ensure
    ::Dependabot::Exceptions.reset!
  end

  # comment added at top push no changes
  # Helper for jobs that are confirmed idempotent and safe to retry on worker shutdown
  def self.retry_on_dirty_exit(&block)
    retry_on Aqueduct::Worker::JobKilled, wait: 60.seconds, &block
  end

  # Helper to retry on "expected" exceptions such as when the database is down. Job must be idempotent.
  def self.retry_on_recoverable_database_exceptions(wait: :polynomially_longer, attempts: 5, &block)
    ::Dependabot::Exceptions::RECOVERABLE_DATABASE_EXCEPTION_CLASSES.each do |error_class|
      retry_on error_class, wait: wait, attempts: attempts, &block
    end
  end

  # Helper to retry on "expected" exceptions such as when the aqueduct api is down. Job must be idempotent.
  def self.retry_on_recoverable_aqueduct_exceptions(wait: :polynomially_longer, attempts: 5, &block)
    ::Dependabot::Exceptions::RECOVERABLE_AQUEDUCT_EXCEPTION_CLASSES.each do |error_class|
      retry_on error_class, wait: wait, attempts: attempts, &block
    end
  end

  # Helper to retry on "expected" exceptions such as when redis is unavailable. Job must be idempotent.
  def self.retry_on_recoverable_redis_exceptions(wait: :polynomially_longer, attempts: 5, &block)
    ::Dependabot::Exceptions::RECOVERABLE_REDIS_EXCEPTION_CLASSES.each do |error_class|
      retry_on error_class, wait: wait, attempts: attempts, &block
    end
  end

  # Helper for jobs that are confirmed idempotent and safe to retry when unable to obtain a restraint lock
  def self.retry_on_restraint_unable_to_lock(wait: 3.seconds, job_retry_ttl: 1.hour, &block)
    attempts = job_retry_ttl / wait

    retry_on Restraint::UnableToLock, wait:, attempts:, &block
  end

  # Helper for jobs that are confirmed idempotent and safe to retry when a throttler times out
  def self.retry_on_throttler_timeout(wait: 3.seconds, job_retry_ttl: 1.hour, &block)
    attempts = job_retry_ttl / wait

    retry_on Throttler::TimeoutError, wait:, attempts:, &block
  end

  # If a job is idempotent these are recommended retries to use
  def self.default_retries_for_idempotent_jobs(&block)
    retry_on_dirty_exit(&block)
    retry_on_recoverable_database_exceptions(&block)
    retry_on_recoverable_aqueduct_exceptions(&block)
    retry_on_recoverable_redis_exceptions(&block)
    retry_on_restraint_unable_to_lock(&block)
    retry_on_throttler_timeout(&block)
  end

  private

  def exception_context
    {
      transaction: exception_transaction,
      "code.namespace": self.class.name,
      "gh.aqueduct.job.id": job_id,
      "gh.aqueduct.queue.name": queue_name,
      "messaging.active_job.retry": executions.positive?,
      "messaging.active_job.executions": executions,
    }
  end

  def instrument_error(error)
    rollup = Digest::MD5.hexdigest("#{error.class}#{exception_transaction}")
    ::Dependabot::Exceptions.report(error, { rollup: rollup })

    job_name = self.class.name.underscore
    error_name = error.class.name.underscore

    Dependabot::Logger.error(
      msg: "#{self.class.name} encountered an error",
      "exception.message": error.message,
      "exception.type": error.class.name
    )
    MetricsClient.increment("job.failed",
                            tags: { job: job_name, queue: queue_name, error: error_name },)
  end

  def log_context
    {
      "code.namespace": self.class.name,
      "gh.aqueduct.job.id": job_id,
      "gh.aqueduct.queue.name": queue_name,
      "messaging.active_job.retry": executions.positive?,
      "messaging.active_job.executions": executions,
    }
  end

  def exception_transaction
    self.class.name
  end
end
