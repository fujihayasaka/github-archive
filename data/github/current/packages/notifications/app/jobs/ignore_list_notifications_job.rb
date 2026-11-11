# typed: true
# frozen_string_literal: true

# Public: Async fallback for muting repository-level notifications. Calls
# Notifications::Subscriptions.mute_repository within write throttle.
#
# In Newsies, "list" is the generic term for any top-level subscribable entity (Repository
# or Team). The caller first attempts the operation synchronously, and only enqueues this
# job as an async retry fallback if the synchronous attempt fails.
#
# Enqueued by: Restorable::WatchedRepository.ignore_list
# (packages/restorables/app/models/restorable/watched_repository.rb) when the synchronous
# mute attempt fails during state recovery. When a user had previously muted a repository,
# this job is the fallback path for re-establishing that mute during recovery.
#
# Example:
#
#  > user = User.find_by_login("jonmagic")
#  > repo = Repository.with_name_with_owner("github/linguist")
#  > response = GitHub.newsies.ignore_list(user, repo)
#  > if response.failed?
#  >   IgnoreListNotificationsJob.perform_later(user.id, repo.id)
#  > end
class IgnoreListNotificationsJob < ApplicationJob
  queue_as :list_subscribe

  use_replicas ApplicationRecord::Mysql1, ApplicationRecord::Repositories

  class RetryableError < RuntimeError ; end
  retry_on RetryableError

  retry_on_dirty_exit

  def perform(user_id, repository_id)
    user = User.find_by(id: user_id)
    return unless user.present?

    repository = T.let(nil, T.nilable(Repositories::IRepository))
    repository = Repositories.domain.by_id(repository_id)
    return unless repository.present?
    return unless repository.is_a?(Repository)

    success = Newsies::ListSubscription.throttle_writes do
      Notifications::Subscriptions.mute_repository(user, repository)
    end

    raise RetryableError unless success
  end
end
