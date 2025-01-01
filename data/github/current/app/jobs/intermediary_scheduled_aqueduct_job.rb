# typed: true
# frozen_string_literal: true

class IntermediaryScheduledAqueductJob < ApplicationJob
  extend T::Sig
  queue_as :scheduled_jobs

  retry_on_dirty_exit

  sig { params(serialized_job_json: String, enqueue_at: T.any(Time, Numeric)).void }
  def perform(serialized_job_json, enqueue_at)
    if enqueue_at.to_i <= GitHub::Aqueduct::MAX_DELIVERY_TIMESTAMP_FUTURE_DURATION.from_now.to_i
      serialized_job = JSON.parse(serialized_job_json)
      job_class = serialized_job["job_class"].safe_constantize
      job = job_class.new
      job.set(wait_until: Time.at(enqueue_at))
      job.deserialize(serialized_job)
      job.enqueue
    else
      self.class.
        set(wait: GitHub::Aqueduct::MAX_DELIVERY_TIMESTAMP_FUTURE_DURATION).
        perform_later(serialized_job_json, enqueue_at)
    end
  end
end
