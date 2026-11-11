# typed: true
# frozen_string_literal: true

# Subscribes a user to watch a repository via User#watch_repo, which enforces
# permission checks (pullable_by?, blocking?, subscription-limit) before calling
# Notifications::Subscriptions.subscribe_to_repository.
#
# This is the guarded, user-initiated subscription path. When the synchronous
# subscribe_to_repository call fails during a user action (Watch button,
# REST API), watch_repo_with_result enqueues this job as an async retry.
# The job passes enqueue: false so it will not re-enqueue itself on failure.
#
# Note: If you need an unguarded subscription path without permission or limit
# checks (e.g., system-level bulk state recovery), see
# SubscribeToListNotificationsJob, which calls subscribe_to_repository
# directly and is used by Restorables where the subscription was previously
# valid.
#
# Enqueued by: User::NotificationsDependency#watch_repo_with_result as an
# async retry fallback when the synchronous subscribe fails. Triggered when
# a user clicks the Watch button (NotificationsController) or calls the REST
# API (PUT /repos/:owner/:repo/subscription).
class UserWatchRepoJob < ApplicationJob
  queue_as :list_subscribe

  class RetryableError < RuntimeError ; end
  retry_on RetryableError, wait: :polynomially_longer
  retry_on_dirty_exit

  use_replicas ApplicationRecord::Mysql1,
    ApplicationRecord::Repositories

  def perform(user_id, repo_id)
    return unless user = User.find_by(id: user_id)
    repo = Repositories.domain.by_id(repo_id)
    return unless repo

    # We use Domain::Notifications for throttling because user.watch_repo
    # writes using the ListSubscription and ThreadTypeSubscription
    # models which both belong to the Notifications domain.
    with_write do
      ApplicationRecord::Domain::Notifications.throttle do
        return if user.watch_repo(repo, enqueue: false)
        raise RetryableError
      end
    end
  end
end
