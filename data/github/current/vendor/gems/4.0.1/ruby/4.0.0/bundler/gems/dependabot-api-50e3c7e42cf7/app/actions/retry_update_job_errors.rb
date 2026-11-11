# frozen_string_literal: true

class RetryUpdateJobErrors
  MAX_UPDATE_JOBS_TO_RETRY = 1000

  def initialize(start_time:, end_time:, error_type:, limit: MAX_UPDATE_JOBS_TO_RETRY)
    @start_time = start_time
    @end_time = end_time
    @error_type = error_type
    @limit = limit
  end

  def run
    jobs = UpdateJob.where(id: update_job_ids).includes(update_config: :last_update_run)
    jobs_to_retry = jobs.reject do |job|
      job.update_config.last_update_run&.created_at.to_i > end_time.to_i
    end

    jobs_to_retry.first(limit).each(&:retry!)
  end

  def update_job_ids
    UpdateJobError.
      where(error_type: error_type).
      where(created_at: start_time..end_time).
      pluck(:update_job_id)
  end

  private

  attr_reader :start_time, :end_time, :error_type, :limit
end
