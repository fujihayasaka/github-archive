# typed: true
# frozen_string_literal: true

# Updates `topics.applied_count` for records with new `repository_topics` rows since the last run.
#
# The `applied_count` column is a denormalization of `repository_topics.topic_id` where the
# `repository_topics` row would be considered "applied," and is used in various Topic queries.
class CalculateTopicAppliedCountsJob < ApplicationJob
  default_to_write_connection! # rubocop:todo GitHub/JobsDoNotDefaultToWriteConnection

  queue_as :calculate_topic_applied_counts

  retry_on_dirty_exit

  schedule interval: 1.hour

  locked_by timeout: 10.minutes, key: ->(job) { job.class.name }

  exempt_from_tenant_context_requirement

  # Public: Updates `topics.applied_count` for all topics.
  #
  # batch_size              - The number of topics to update per batch.
  # duration                - The amount of time in seconds that each job instance can run
  #                           for. After this time is elapsed, if there are still more
  #                           batches to process, another job is enqueued to finish the work,
  #                           and the current job terminates.
  # last_processed_topic_id - The topic id to resume processing after. The job will only process
  #                           topics with an id greater than this.
  def perform(batch_size: 50, duration: 60, last_processed_topic_id: 0)
    end_at = Time.current + duration

    loop do
      ids = ActiveRecord::Base.connected_to(role: :reading) do
        Topic.where("id > ?", last_processed_topic_id)
                .order(:id)
                .limit(batch_size)
                .pluck(:id)
      end

      break if ids.empty?

      Topic.update_applied_counts(ids)

      last_processed_topic_id = ids.last

      if Time.current >= end_at
        clear_lock
        CalculateTopicAppliedCountsJob.perform_later(
          batch_size: batch_size,
          duration: duration,
          last_processed_topic_id: last_processed_topic_id,
        )

        break
      end
    end

    true
  end
end
