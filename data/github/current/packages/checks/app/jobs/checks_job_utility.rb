# typed: true
# frozen_string_literal: true

module ChecksJobUtility

  RESTRICT_START_HOUR_TIME = 7 # 7:00 UTC / 3:00 AM EST / 12:00 AM PST
  RESTRICT_END_HOUR_TIME = 19 # 19:00 UTC / 3:00 PM EST / 12:00 PM PST

  RAMP_UP_HOUR_TIME = 19
  RAMP_UP_START_MINUTE_TIME = 0 # Start ramp up time 19:00 UTC / 3:00 PM EST / 12:00 PM PST
  RAMP_UP_END_MINUTE_TIME = 30 # End ramp up time 19:30 UTC / 3:30 PM EST / 12:30 PM PST

  # The number of days to keep checks data for before archiving. For both enterprise and hosted this value is the same and it's not possible for customers
  # to extend records past this duration
  DEFAULT_MAX_ARCHIVE_THRESHOLD_IN_DAYS = 400.days.freeze
  DEFAULT_ARCHIVE_RETENTION_PERIOD_IN_DAYS = 10.days.freeze

  # The amount of days that we have to wait before archiving resources
  def archive_threshold_days
    return GitHub.checks_retention_archive_threshold.days if GitHub.checks_retention_archive_threshold && GitHub.enterprise?

    DEFAULT_MAX_ARCHIVE_THRESHOLD_IN_DAYS
  end

  # The number of days to keep archived checks data before hard deletion
  def delete_archived_threshold_days
    return GitHub.checks_retention_delete_threshold.days if GitHub.checks_retention_delete_threshold && GitHub.enterprise?

    DEFAULT_ARCHIVE_RETENTION_PERIOD_IN_DAYS
  end

  # Used to restrict any high QPS background jobs from running at certain times to reduce load on VTGate
  # Restrict during 3:00 AM EST - 3:00 PM EST (7:00 AM UTC - 7:00 PM UTC) Mon-Friday
  # During this window of time repositories-actions-checks has the highest QPS. See https://app.datadoghq.com/s/59fe6c40c/sfg-9fd-vsy
  def peak_traffic_time?
    current_time = Time.now.utc
    if current_time.sunday? || current_time.saturday?
      false
    else
      if current_time.hour >= RESTRICT_START_HOUR_TIME && current_time.hour < RESTRICT_END_HOUR_TIME
        true
      else
        false
      end
    end
  end

  # The purpose of this function is to smooth out the initial spike in I/O that happens when peak traffic time ends and a large wave of retention jobs suddently kicks in
  # Between 19:00-19:30 UTC (3:00-3:30 PM EST) we want to gradually incrase the number of retention jobs that are running
  def ramp_up_retention_time?
    return false if peak_traffic_time?

    current_time = Time.now.utc
    return false if current_time.sunday? || current_time.saturday?

    if current_time.hour == RAMP_UP_HOUR_TIME && current_time.min >= RAMP_UP_START_MINUTE_TIME && current_time.min < RAMP_UP_END_MINUTE_TIME
      true
    else
      false
    end
  end

  # During the weekend there is significantly less traffic so retention jobs can run with an even larger batch count to process more data
  def weekend_deletion_window?
    current_time = Time.now.utc
    return true if current_time.sunday? || current_time.saturday?
    false
  end

  # Utility class to group IDs by repository_id so that all SQL calls can have the primary sharding key included later
  # Expected input is a list of of plucked repoID and ID pairs in the format [[repository_id, id], [repository_id, id]...]
  # Returns in the format [[repository_id, [id, id, id]], [repository_id, [id, id, id]]...
  def group_by_repository_id(input_data)
    # https://stackoverflow.com/questions/59421316/rails-group-by-column-and-select-column
    input_data.group_by(&:shift).transform_values(&:flatten)
  end

  # Orchestration jobs set concurrency keys for parallel running jobs to keep track of completions
  # Each parallel running job has a slightly different concurrency key and before a new batch of jobs is scheduled previous ones are checked to make sure they finished
  # Kube jobs scheduled on lowworker have a maximum execution time of 5 minutes. If a job hangs, timeouts and gets killed and doesn't get cleared by the
  def set_concurrency_key_for_parallel_job(concurrent_job_key)
    ActiveRecord::Base.connected_to(role: :writing) do
      kv(concurrent_job_key).set(concurrent_job_key, "true", expires: 5.minutes.from_now)
    end
  end

  # Clear a concurrent_job_key after a parallel running job finishes so the orchestration knows a specific job has finished
  def clear_concurrency_key_for_batch(concurrent_job_key)
    ActiveRecord::Base.connected_to(role: :writing) do
      kv(concurrent_job_key).del(concurrent_job_key)
    end
  end

  def concurrency_key_for_batch_exists?(concurrent_job_key)
    kv(concurrent_job_key).exists(concurrent_job_key).value!
  end

  def set_concurrency_key_for_batch(concurrent_job_key)
    ActiveRecord::Base.connected_to(role: :writing) do
      # Kube jobs scheduled on lowworker have a maximum execution time of 5 minutes. If a job hangs and gets killed, they concurrent_job_key will just expire
      kv(concurrent_job_key).set(concurrent_job_key, "true", expires: 5.minutes.from_now)
    end
  end

  def kv(concurrent_job_key)
    Actions::KV.for_key(concurrent_job_key)
  end
end
