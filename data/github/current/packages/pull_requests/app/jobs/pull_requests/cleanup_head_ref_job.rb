# typed: true
# frozen_string_literal: true

module PullRequests
  class CleanupHeadRefJob < ApplicationJob
    queue_as :pull_request_head_ref_deletion

    # Allow write connections to these clusters.
    use_primaries ApplicationRecord::IssuesPullRequests,
      ApplicationRecord::Spokes

    use_replicas ApplicationRecord::Mysql1,
      ApplicationRecord::Repositories,
      ApplicationRecord::Collab,
      ApplicationRecord::Configurations,
      ApplicationRecord::IamAbilities,
      ApplicationRecord::Permissions

    RETRY_ATTEMPTS = 10

    retry_on_dirty_exit

    retry_on GitHub::DGit::ThreepcError, attempts: RETRY_ATTEMPTS, wait: :polynomially_longer
    retry_on GitHub::DGit::ThreepcBusyError, attempts: RETRY_ATTEMPTS, wait: :polynomially_longer
    retry_on GitHub::DGit::ThreepcFailedToLock, attempts: RETRY_ATTEMPTS, wait: :polynomially_longer

    sig { params(pull_request: ::PullRequest, actor: T.nilable(::User)).void }
    def perform(pull_request:, actor:)
      return unless pull_request.repository&.feature_enabled?(:async_delete_branch_on_merge)

      if actor.is_a?(Bot) && !actor.installation
        actor.async_load_installation_for(pull_request.repository).sync
      end

      pull_request.cleanup_head_ref(actor)
    end
  end
end
