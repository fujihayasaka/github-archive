# typed: strict
# frozen_string_literal: true

module PullRequests
  module MergeCommit
    sig { params(pull_request: PullRequest, priority: Symbol).void }
    def self.enqueue_create(pull_request:, priority: :low)
      return unless pull_request.open?
      return unless repository = pull_request.repository

      # currently_mergeable? is not a true predicate method and in this
      # particular scenario we are specifically interested in the nil state.
      # Therefore we need to do this somewhat awkward looking nil check
      # on a predicate method's return value.
      unless FeatureFlag.vexi.enabled?(:pull_requests_reduced_merge_commits, repository, default: false)
        return unless pull_request.currently_mergeable?.nil?
      end

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
        "catalog_service:#{GitHub.context[:catalog_service]}",
        "feature:create"
      ])
    end

    sig { params(pull_request: PullRequest).void }
    def self.enqueue_delete(pull_request:)
      DeleteMergeCommitsJob.perform_later(pull_request)

      GitHub.dogstats.increment("merge_commit.enqueued", tags: [
        "from:#{GitHub.context[:from].presence || GitHub.context[:job].presence || "unknown"}",
        "catalog_service:#{GitHub.context[:catalog_service]}",
        "feature:delete"
      ])
    end

    CACHEABLE_TTL = T.let(10.minutes, ActiveSupport::Duration)

    sig { params(pull_request: PullRequest, merge_commit: T.nilable(::Commit)).returns(T::Boolean) }
    def self.cacheable?(pull_request:, merge_commit:)
      max_age = CACHEABLE_TTL.ago
      head_sha = pull_request.mergeable_head_sha
      base_sha = pull_request.mergeable_base_sha
      mergeable = pull_request.mergeable

      return false if head_sha.nil? || head_sha.blank? || base_sha.nil? || base_sha.blank?
      return false if mergeable == false

      if merge_commit
        created_at = merge_commit.created_at
        commit_base_sha, commit_head_sha = merge_commit.parent_oids

        if commit_base_sha.blank? || commit_head_sha.blank?
          false # Merge commits should always have 2 parents, if not, something wrong has happened.
        elsif mergeable.nil? && has_conflict?(pull_request:)
          cacheable_with_conflict?(pull_request:, max_age:)
        elsif base_sha == commit_base_sha && head_sha == commit_head_sha
          true  # Up to date commits are valid.
        elsif created_at && created_at > max_age && commit_head_sha == head_sha
          true  # If the commit was created within the TTL with a matching head_sha, it's still valid.
        else
          false
        end
      else
        # If we don't have a merge commit, we may have a conflict record.
        if has_conflict?(pull_request:)
          return cacheable_with_conflict?(pull_request:, max_age:)
        end

        false # We don't have a merge commit or conflict record, generate a new one.
      end
    end

    sig { params(pull_request: PullRequest).returns(T::Boolean) }
    def self.has_conflict?(pull_request:)
      head_sha = pull_request.mergeable_head_sha
      base_sha = pull_request.mergeable_base_sha

      begin
        PullRequestConflict.where(pull_request:, base_sha:, head_sha:, conflict_type: %i[merge_conflict rebase_conflict]).exists?
      rescue *PullRequests::MergeCommit::Command::DATABASE_ERRORS
        false
      end
    end

    sig { params(pull_request: PullRequest, max_age: ActiveSupport::TimeWithZone).returns(T::Boolean) }
    def self.cacheable_with_conflict?(pull_request:, max_age:)
      # Utilize the creation timestamp of this record as a cache source.
      head_sha = pull_request.mergeable_head_sha
      conflict_created_at = begin
        PullRequestConflict.where(pull_request:, head_sha:, conflict_type: %i[merge_conflict rebase_conflict]).maximum(:created_at)
      rescue *PullRequests::MergeCommit::Command::DATABASE_ERRORS => exception
        Failbot.report(exception)
        nil # Treat database failures as no data point.
      end

      if conflict_created_at
        conflict_created_at > max_age
      else
        false
      end
    end

    # Determine if the repository is enrolled in the Merge Commit Request engine.
    sig { params(repository: T.nilable(Repository)).returns(T::Boolean) }
    def self.enabled_for?(repository)
      # Deal with the potentially `nil` Repository.
      return false unless repository

      # Stops merge commit request creation and the queueing of CreateMergeCommitsJobs and subsequent
      # BatchRefUpdatesJobs. Reverts to using the CreatePullRequestMergeCommitJob for merge commit generation
      return false if MergeCommitRequest.paused_for?(repository)

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
