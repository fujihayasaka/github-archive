# rubocop:todo GitHub/EnforcePackageAppStructure
# typed: true
# frozen_string_literal: true

# Recalculates the cached subscriber count for a single repository.
class CalculateSubscribersCountByRepoJob < ApplicationJob
  include ActiveJob::InitiallyEnqueuedAt

  queue_as :calculate_subscribers_count

  retry_on_dirty_exit

  discard_on ActiveJob::DeserializationError

  # repo       - The Repository
  # start_time - Time the job was initially enqueued
  sig { params(repo: Repository, start_time: T.nilable(Time)).void }
  def perform(repo, start_time = initially_enqueued_at)
    Repository.throttle do
      # Compute the authoritative spam-filtered subscriber count via the Notifications::Subscriptions module.
      count = ActiveRecord::Base.connected_to(role: :reading) do
        Notifications::Subscriptions.count_repository_subscribers(T.must(repo.id), exclude_spammy_users: true)
      end
      if count
        with_write do
          Repositories.domain.update_subscribers_count(repository_id: T.must(repo.id), count: count)
        end
      end
    end

    duration = (Time.now.utc - T.cast(start_time, Time)) * 1_000
    GitHub.dogstats.distribution("calculate_subscribers_count_by_repo.dist.duration", duration)
  end
end
