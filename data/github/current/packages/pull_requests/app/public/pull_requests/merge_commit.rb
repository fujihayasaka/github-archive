# typed: strict
# frozen_string_literal: true

module PullRequests
  module MergeCommit
    sig { params(pull_request: PullRequest, priority: Symbol).void }
    def self.enqueue_create(pull_request:, priority: :low)
      return unless pull_request.open?

      # currently_mergeable? is not a true predicate method and in this
      # particular scenario we are specifically interested in the nil state.
      # Therefore we need to do this somewhat awkward looking nil check
      # on a predicate method's return value.
      return unless pull_request.currently_mergeable?.nil?

      return unless repository = pull_request.repository
      return unless repository_id = repository.id
      return unless pull_request_id = pull_request.id

      if enabled_for?(repository)
        priority = case priority
        when :high
          Enums::Priority::High.serialize
        when :medium
          Enums::Priority::Medium.serialize
        else # includes :low
          Enums::Priority::Low.serialize
        end

        CreateMergeCommitsJob.perform_later(pull_request, priority:)
      else
        CreatePullRequestMergeCommitJob.perform_later(pull_request_id)
      end

      GitHub.dogstats.increment("merge_commit.enqueued", tags: [
        "from:#{GitHub.context[:from].presence || GitHub.context[:job].presence || "unknown"}",
        "catalog_service:#{GitHub.context[:catalog_service]}"
      ])
    end

    # Determine if the repository is enrolled in the Merge Commit Request engine.
    sig { params(repository: T.nilable(Repository)).returns(T::Boolean) }
    def self.enabled_for?(repository)
      # Deal with the potentially `nil` Repository.
      return false unless repository

      # Stops merge commit request creation and the queueing of CreateMergeCommitsJobs and subsequent
      # BatchRefUpdatesJobs. Reverts to using the CreatePullRequestMergeCommitJob for merge commit generation
      return false if MergeCommitRequest.paused_for?(repository)

      # Check global feature flag block on merge commit requests
      return false if GitHub.flipper[:disable_mcr_engine].enabled?

      # Default return value
      true
    end

    # Temporary helper method mocked in tests.
    sig { returns(T::Boolean) }
    def self.test_mode?
      Rails.env.test? # rubocop:disable GitHub/DoNotBranchOnRailsEnv
    end
  end
end
