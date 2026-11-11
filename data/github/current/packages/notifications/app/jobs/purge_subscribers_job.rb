# typed: strict
# frozen_string_literal: true

# Job for purging notification subscriptions from users who no longer have
# access to a repository. Used for non-restorable paths such as repository
# transfers and manual corrections. Batches through 1000 users at a time,
# rescheduling itself for each batch.
#
# This job delegates to Notifications::PurgeSubscribersService for merged
# cursor pagination, access checking, and subscription deletion.
#
# Enqueued by: Repository::NotificationsDependency
# (packages/notifications/app/models/repository/notifications_dependency.rb)
# on permanent repository deletion.
class PurgeSubscribersJob < ApplicationJob
  include ActiveJob::InitiallyEnqueuedAt

  use_replicas ApplicationRecord::Collab,
    ApplicationRecord::Configurations,
    ApplicationRecord::Iam,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Mysql1,
    ApplicationRecord::Mysql2,
    ApplicationRecord::Repositories

  BATCH_SIZE = 1000

  queue_as :subscriptions_maintenance

  retry_on_dirty_exit
  retry_on_recoverable_exceptions

  sig { params(repository_id: Integer, user_offset_id: Integer, start_time: T.any(Time, ActiveSupport::TimeWithZone)).void }
  def perform(repository_id, user_offset_id = 0, start_time = initially_enqueued_at)
    return unless repository = Repositories.domain.by_id(repository_id)

    service = Notifications::PurgeSubscribersService.new(repository: repository, job_name: "purge_subscribers")
    batch = service.fetch_next_batch(user_offset_id, batch_size: BATCH_SIZE)

    if batch.any?
      user_ids = service.user_ids_without_access(batch)
      service.async_delete_subscriptions(user_ids) if user_ids.any?
    end

    if batch.size < BATCH_SIZE
      service.report_total_duration(start_time)
    else
      self.class.perform_later(repository_id, T.must(batch.last), start_time)
    end
  end
end
