# typed: strict
# frozen_string_literal: true

class BackgroundInstrumentationJob < ApplicationJob

  queue_as :background_instrumentation_job
  retry_on_recoverable_exceptions
  retry_on_dirty_exit
  retry_on GitHub::Restraint::UnableToLock, wait: ->(_executions) { (rand(30..300)).seconds }, attempts: :unlimited

  RESTRAINT_LOCK_TTL = T.let(5.minutes, Integer)

  sig { params(model: T.untyped, key: Symbol, payloads: T::Array[T::Hash[T.untyped, T.untyped]]).void }
  def perform(model, key, payloads = [])
    self.class.global_job_limit_lock! do
      payloads.each do |payload|
        model.instrument key, payload
      end
    end
  end

  sig { params(block: T.proc.void).void }
  def self.global_job_limit_lock!(&block)
    restraint_key = "background_instrumentation_job-global_limit"
    restraint.lock!(restraint_key, GitHub.max_concurrent_background_instrumentation_jobs, RESTRAINT_LOCK_TTL) do
      block.call
    end
  end

  sig { returns(GitHub::Restraint) }
  def self.restraint
    @restraint ||= T.let(GitHub::Restraint.new, T.nilable(GitHub::Restraint))
  end
end
