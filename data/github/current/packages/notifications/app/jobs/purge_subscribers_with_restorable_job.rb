# typed: true
# frozen_string_literal: true

# Job for purging notification subscriptions from users who no longer have
# access to a repository, with restorable tracking for visibility changes.
#
# This job is used when a repository's visibility changes (e.g., public → private)
# and the system needs to back up subscription data for potential restoration.
class PurgeSubscribersWithRestorableJob < ApplicationJob
  include ActiveJob::InitiallyEnqueuedAt

  use_replicas ApplicationRecord::Collab,
    ApplicationRecord::Configurations,
    ApplicationRecord::Iam,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Mysql1,
    ApplicationRecord::Mysql2,
    ApplicationRecord::Repositories

  BATCH_SIZE = 1000

  queue_as :notifications

  retry_on_dirty_exit
  retry_on_recoverable_exceptions

  def perform(repository_id, user_offset_id = 0, start_time = initially_enqueued_at, restorable_id:)
    return unless repository = Repositories.domain.by_id(repository_id)

    service = Notifications::PurgeSubscribersService.new(repository: repository, job_name: "restorable")

    batch = service.fetch_next_batch(user_offset_id, batch_size: BATCH_SIZE)

    if user_offset_id == 0
      # First invocation: initialize restorable saving state with estimated batch count.
      expected_batches = [(service.count_all_repository_subscribers.to_f / BATCH_SIZE).ceil, 1].max
      with_write do
        Restorables.domain.visibility_changed_repositories.start_saving_watchers(
          restorable_id: restorable_id,
          remaining: expected_batches
        )
      end
    end

    user_ids = service.user_ids_without_access(batch)
    if user_ids.size > 0
      service.async_delete_subscriptions(user_ids, restorable_id: restorable_id)
    else
      # This batch had no users to process, so mark it complete here.
      with_write do
        Restorables.domain.visibility_changed_repositories.report_saving_watchers_progress(
          restorable_id: restorable_id,
        )
      end
    end

    if batch.size < BATCH_SIZE
      # All users processed — finalize restorable as a safety net in case
      # the remaining count drifted due to async deletions between batches.
      with_write do
        Restorables.domain.visibility_changed_repositories.finalize_saving_watchers(
          restorable_id: restorable_id,
        )
      end
      service.report_total_duration(start_time)
    else
      self.class.perform_later(repository_id, batch.last, start_time, restorable_id: restorable_id)
    end
  end
end
