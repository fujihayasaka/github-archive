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

  class RetryableError < RuntimeError ; end
  retry_on RetryableError

  retry_on_dirty_exit

  def perform(user_id, repository_id)
    user = T.let(nil, T.nilable(User))
    repository = T.let(nil, T.nilable(Repositories::IRepository))
    user = User.find_by(id: user_id)
    repository = Repositories.domain.by_id(repository_id)

    return unless user.present? && repository.present?

    response = Newsies::ListSubscription.throttle_writes { GitHub.newsies.ignore_list(user, repository) }
    raise RetryableError if response.failed?
  end
end
