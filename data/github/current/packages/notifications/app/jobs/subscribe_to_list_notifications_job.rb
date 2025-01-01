# typed: true
# frozen_string_literal: true

# Public: Use this job to call GitHub.newsies.subscribe_to_list asynchronously.
#
# Example:
#
#  > user = User.find_by_login("jonmagic")
#  > repo = Repository.with_name_with_owner("github/linguist")
#  > response = GitHub.newsies.subscribe_to_list(user, repo)
#  > if response.failed?
#  >   SubscribeToListNotificationsJob.perform_later(user.id, repo.id)
#  > end
#
class SubscribeToListNotificationsJob < ApplicationJob
  queue_as :notifications

  class RetryableError < RuntimeError ; end
  retry_on RetryableError

  retry_on_dirty_exit

  def perform(user_id, repository_id)
    return unless user = User.find_by(id: user_id)
    repository = if FeatureFlag.vexi.enabled?(:repos_domain_find_by, default: false)
      Repositories.domain.by_id(repository_id)
    else
      Repository.find_by(id: repository_id)
    end
    return unless repository

    response = Newsies::ListSubscription.throttle_writes { GitHub.newsies.subscribe_to_list(user, repository) }
    raise RetryableError if response.failed?
  end
end
