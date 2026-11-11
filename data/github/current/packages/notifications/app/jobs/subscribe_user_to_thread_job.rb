# typed: true
# frozen_string_literal: true

# Subscribes a user to a commit thread by calling GitHub.newsies.subscribe_to_thread
# with write throttling on ThreadSubscription operations.
#
# Enqueued by: Newsies::Service via GitHub.newsies.async_subscribe_to_thread, used for
# async commit comment author subscriptions.
class SubscribeUserToThreadJob < ApplicationJob
  queue_as :thread_subscribe

  class SubscribeError < StandardError; end
  retry_on SubscribeError, wait: :polynomially_longer
  retry_on_dirty_exit

  use_replicas ApplicationRecord::Mysql1,
    ApplicationRecord::Repositories

  # Subscribes a User to a thread, by calling
  # GitHub.newsies.subscribe_user_to_thread
  def perform(user_id, repository_id, commit_oid, reason = nil, options = {})
    # Support both string and symbol keys from legacy RockQueue.
    options.deep_stringify_keys!

    user, repo = nil
    user = User.find_by(id: user_id)
    repo = T.cast(Repositories.domain.by_id(repository_id), T.nilable(Repository)) # rubocop:todo GitHub/AvoidCast

    return unless user && repo
    return unless commit = repo.commits.find(commit_oid)

    response = with_write do
      Newsies::ThreadSubscription.throttle do
        GitHub.newsies.subscribe_to_thread(user, repo, commit, reason)
      end
    end

    raise SubscribeError unless response.success?
  end
end
