# frozen_string_literal: true

module ChatopTimeRange
  extend ActiveSupport::Concern

  BATCH_SIZE = 1_000_000

  private

  # Converts a time range to an ID range by finding the first and last
  # UpdateJob IDs created within the time range using the created_at index
  def id_range_for_time_range(start_time, end_time)
    start_id = UpdateJob.
               from("update_jobs FORCE INDEX (index_update_jobs_on_created_at)").
               where(created_at: start_time..).
               order(:created_at).
               pick(:id)

    return [nil, nil] unless start_id

    end_id = UpdateJob.
             from("update_jobs FORCE INDEX (index_update_jobs_on_created_at)").
             where(created_at: ..end_time).
             order(created_at: :desc).
             pick(:id)

    [start_id, end_id]
  end

  # Yields batches of ID ranges to process large ID ranges in chunks
  def each_id_batch(start_id, end_id, batch_size: BATCH_SIZE)
    current_start = start_id

    while current_start <= end_id
      current_end = [current_start + batch_size - 1, end_id].min
      yield current_start, current_end
      current_start = current_end + 1
    end
  end
end
