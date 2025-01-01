# typed: true
# frozen_string_literal: true

class UserForkCountJob < ApplicationJob
  queue_as :user_fork_count
  retry_on_dirty_exit

  def perform(user_id)
    return unless FeatureFlag.vexi.enabled_or_raise?(:repo_fork_count_job) # rubocop:disable GitHub/FeatureManagement/NoVexiEnabledOrRaiseUsage

    user = User.find_by(id: user_id)
    return unless user

    Failbot.push("gh.user.id": user_id)

    # for this spammy user, recalculate the network fork count for each of their forks
    user.repositories.active.forks.in_batches(of: 1000) do |batch|
      batch.each do |repo|
        if repo.parent_id.present?
          # Run this job only once and in one hour. Ignore this request if it is already scheduled.
          RepositoryForkCountJob.enqueue_once_per_interval(args: [repo.parent_id], interval: 60 * 60)
        end
      end
    end
  end
end
