# typed: true
# frozen_string_literal: true

class CheckStepsDeleteJob < ApplicationJob
  include GitHub::Tracing
  include ChecksJobUtility

  DELETE_BATCH_SIZE = 100
  READ_BATCH_SIZE = 5000

  queue_as :delete_old_check_steps
  retry_on_dirty_exit
  retry_on_recoverable_exceptions

  trace_method :perform
  trace_method :delete_steps

  # Deletes a batch of check steps between a start and end id (inclusive)
  def perform(start_id:, end_id:, concurrent_job_key:)
    raise ArgumentError, "start_id must be provided." unless start_id.present?
    raise ArgumentError, "end_id must be provided." unless end_id.present?
    raise ArgumentError, "concurrent_job_key must be provided." unless concurrent_job_key.present?

    lock! do
      delete_steps(start_id: start_id, end_id: end_id, concurrent_job_key: concurrent_job_key)
    rescue ActiveRecord::RecordNotFound, StandardError => e # rubocop:todo Lint/RescueException
      Failbot.report(e)
      raise e
    end
  end

  # The amount of days that we have to wait before permanently deleting a check step
  # See actions_retention_limit.rb, the maximum allowed retention period is 400 days for all environments
  def self.delete_threshold_days
    DEFAULT_MAX_ARCHIVE_THRESHOLD_IN_DAYS
  end

  private

  def lock!
    restraint = GitHub::Restraint.new
    lock_key = self.class.name
    max_concurrent_jobs = 20 # Maximum of 20 concurrent jobs
    lock_ttl = 5.minutes
    restraint.lock!(T.must(lock_key), max_concurrent_jobs, lock_ttl) do
      yield
    end
  rescue GitHub::Restraint::UnableToLock
    # Skip job if we try to run while lock is held
    GitHub.dogstats.increment("checks.delete_old_check_steps.unable_to_lock")
  end

  def delete_steps(start_id:, end_id:, concurrent_job_key:)
    total_delete_count = 0

    loop do
      # Read from replicas when fetching the IDs to delete, there is a small chance that due to replication lag certain IDs no longer exist because we're deleting so fast concurrently. But better to do so in order to reduce load on the primary
      old_steps_to_delete = CheckStep
        .where("created_at <= :created_at AND id BETWEEN :start_id AND :end_id", created_at: self.class.delete_threshold_days.ago, start_id: start_id, end_id: end_id)
        .order(id: :asc)
        .limit(READ_BATCH_SIZE)
        .pluck(:repository_id, :id)

      break if old_steps_to_delete.empty?

      repo_id_pairs = group_by_repository_id(old_steps_to_delete)

      repo_id_pairs.each do |repository_id, step_ids|
        step_ids.in_groups_of(DELETE_BATCH_SIZE) do |batch|
          ActiveRecord::Base.connected_to(role: :writing) do
            deleted_count = CheckStep.throttle do
              CheckStep.where(repository_id: repository_id, id: batch).delete_all
            end
            total_delete_count = total_delete_count + deleted_count
          end
        end
      end
    end

    GitHub.dogstats.count("checks.delete_check_steps_job.deleted", total_delete_count)

    # clear the concurrent job key so that the next set of jobs can be scheduled fin the orchestration delete job
    clear_concurrency_key_for_batch(concurrent_job_key)
  end
end
