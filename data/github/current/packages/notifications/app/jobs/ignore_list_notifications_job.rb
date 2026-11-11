# typed: true
# frozen_string_literal: true

# Public: Use this job to call GitHub.newsies.ignore_list asynchronously.
#
# Example:
#
#  > user = User.find_by_login("jonmagic")
#  > repo = Repository.with_name_with_owner("github/linguist")
#  > response = GitHub.newsies.ignore_list(user, repo)
#  > if response.failed?
#  >   IgnoreListNotificationsJob.perform_later(user.id, repo.id)
#  > end
#
class IgnoreListNotificationsJob < ApplicationJob
  queue_as :notifications

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

    success = Newsies::ListSubscription.throttle_writes do
      Notifications::Subscriptions.mute_repository(user, repository)
    end

    raise RetryableError unless success
  end
end
