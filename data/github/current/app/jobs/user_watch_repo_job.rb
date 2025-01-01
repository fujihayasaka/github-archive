# rubocop:todo GitHub/EnforcePackageAppStructure
# typed: true
# frozen_string_literal: true

class UserWatchRepoJob < ApplicationJob
  queue_as :notifications

  class RetryableError < RuntimeError ; end
  retry_on RetryableError, wait: :polynomially_longer
  retry_on_dirty_exit

  def perform(user_id, repo_id)
    return unless user = User.find_by(id: user_id)
    return unless repo = Repository.find_by(id: repo_id)

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
