# typed: true
# frozen_string_literal: true

# Public: Subscribes a user to repository-level notifications by calling
# Notifications::Subscriptions.subscribe_to_repository directly, without any
# permission checks or subscription-limit guards.
#
# This is an unguarded, system-level subscription path intended for bulk state
# recovery (Restorables). Because the system is restoring a previously-valid
# subscription, permission and limit checks are intentionally skipped.
#
# Note: If you need a guarded subscription path with permission and
# subscription-limit checks, see UserWatchRepoJob, which routes through
# User#watch_repo (enforces pullable_by?, blocking?, and subscription-limit)
# before calling the same underlying subscribe_to_repository method.
#
# Enqueued by: Restorable::WatchedRepository.subscribe_to_list
# (packages/restorables/app/models/restorable/watched_repository.rb) when the
# synchronous subscribe attempt fails during state recovery (e.g., user
# re-added to org).
#
# Example:
#
#  > user = User.find_by_login("jonmagic")
#  > repo = Repository.with_name_with_owner("github/linguist")
#  > response = GitHub.newsies.subscribe_to_list(user, repo)
#  > if response.failed?
#  >   SubscribeToListNotificationsJob.perform_later(user.id, repo.id)
#  > end
class SubscribeToListNotificationsJob < ApplicationJob
  queue_as :list_subscribe

  class RetryableError < RuntimeError ; end
  retry_on RetryableError

  retry_on_dirty_exit

  use_replicas ApplicationRecord::Mysql1,
    ApplicationRecord::Repositories

  def perform(user_id, repository_id)
    user = User.find_by(id: user_id)
    return unless user.present?

    repository = T.let(nil, T.nilable(Repositories::IRepository))
    repository = Repositories.domain.by_id(repository_id)
    return unless repository.present?
    return unless repository.is_a?(Repository)

    success = Newsies::ListSubscription.throttle_writes do
      Notifications::Subscriptions.subscribe_to_repository(user, repository)
    end
    raise RetryableError unless success
  end
end
