# typed: true
# frozen_string_literal: true

class SubscribeUserToThreadJob < ApplicationJob
  queue_as  :kubernetes_notifications

  class SubscribeError < StandardError; end
  retry_on SubscribeError, wait: :polynomially_longer
  retry_on_dirty_exit

  # Subscribes a User to a thread, by calling
  # GitHub.newsies.subscribe_user_to_thread
  def perform(user_id, repository_id, commit_oid, reason = nil, options = {})
    # Support both string and symbol keys from legacy RockQueue.
    options.deep_stringify_keys!

    user, repo = nil
    user = User.find_by(id: user_id)
    repo = if FeatureFlag.vexi.enabled?(:repos_domain_find_by, default: false)
      T.cast(Repositories.domain.by_id(repository_id), T.nilable(Repository)) # rubocop:todo GitHub/AvoidCast
    else
      Repository.find_by(id: repository_id)
    end

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
