# rubocop:todo GitHub/EnforcePackageAppStructure
# typed: true
# frozen_string_literal: true

# Recalculates cached subscriber counts for every repository watched by `user`.
class CalculateSubscribersCountByUserJob < ApplicationJob
  include ActiveJob::InitiallyEnqueuedAt

  queue_as :calculate_subscribers_count

  retry_on_dirty_exit

  discard_on ActiveJob::DeserializationError

  BATCH_SIZE = 100

  # user       - The User
  # offset_id  - Integer list_id offset for batch pagination
  # start_time - Time the job chain was initially enqueued
  def perform(user, offset_id = 0, start_time = initially_enqueued_at)
    watched_list_ids = Newsies::ListSubscription
      .for_user(user.id)
      .where(list_type: "Repository", ignored: false)
      .where("list_id > ?", offset_id)
      .order(:list_id)
      .limit(BATCH_SIZE)
      .pluck(:list_id)

    repos = Repository.where(id: watched_list_ids).to_a

    if repos.any?
      Repository.throttle do
        repos.each do |repo|
          # Compute the authoritative spam-filtered subscriber count via the Notifications::Subscriptions module.
          count = ActiveRecord::Base.connected_to(role: :reading) do
            Notifications::Subscriptions.count_repository_subscribers(T.must(repo.id), exclude_spammy_users: true)
          end
          next unless count

          with_write do
            Repositories.domain.update_subscribers_count(repository_id: T.must(repo.id), count: count)
          end
        end
      end
    end

    if watched_list_ids.size >= BATCH_SIZE
      self.class.perform_later(user, watched_list_ids.last, start_time)
    else
      duration = (Time.now.utc - T.cast(start_time, Time)) * 1_000
      GitHub.dogstats.distribution("calculate_subscribers_count_by_user.dist.duration", duration)
    end
  end
end
