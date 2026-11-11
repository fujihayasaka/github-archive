# typed: strict
# frozen_string_literal: true

module PullRequests
  module MergeCommit
    module CreateCommits
      class Loader
        include GitHub::Memoizer

        sig { params(pull_request: PullRequest, repository: Repository, priority: Integer).void }
        def initialize(pull_request:, repository:, priority: 0)
          @pull = pull_request
          @repo = repository # Note that requiring repository here requires the caller to handle Enums::InvalidRequestReason::MissingRepository
          @priority = priority
        end

        sig { returns(T.any(Request, Enums::InvalidRequestReason)) }
        memoize def request
          if @pull.in_merge_queue?
            return Enums::InvalidRequestReason::EnqueuedInMergeQueue
          end

          unless @pull.issue # domain-isolation-query-violation:ignore:packages/issues (SELECT)
            return Enums::InvalidRequestReason::MissingIssue
          end

          if @pull.merged_at? || @pull.closed?
            return Enums::InvalidRequestReason::ClosedOrMerged
          end

          unless base_repository = determine_base_repository
            return Enums::InvalidRequestReason::MissingBaseRepository
          end

          unless head_repository = determine_head_repository
            return Enums::InvalidRequestReason::MissingHeadRepository
          end

          base_ref_name = @pull.qualified_base_ref_name
          head_ref_name = @pull.qualified_head_ref_name
          rebase_ref_name = @pull.rebase_ref
          merge_commit_sha = @pull.merge_commit_sha

          refs.request(base_repository, base_ref_name)
          refs.request(head_repository, head_ref_name)
          refs.request(base_repository, rebase_ref_name) if include_rebase_commit?

          with_telemetry(:refs) { refs.execute }

          commits.request(base_repository, merge_commit_sha)

          if include_rebase_commit?
            potential_rebase_commit_sha = refs.read(base_repository, rebase_ref_name)
            commits.request(base_repository, potential_rebase_commit_sha)
          end

          with_telemetry(:commits) { commits.execute }

          unless base_branch_sha = refs.read(base_repository, base_ref_name)
            return Enums::InvalidRequestReason::MissingBaseBranchSha
          end

          unless head_branch_sha = refs.read(head_repository, head_ref_name)
            return Enums::InvalidRequestReason::MissingHeadBranchSha
          end

          # If we've generated the commit but it has not performed the batch ref update yet, skip it.
          if duplicate_merge_commit_request?(base_branch_sha:, head_branch_sha:)
            return Enums::InvalidRequestReason::DuplicateRequest
          end

          merge_commit = read_and_determine_commit(base_repository, merge_commit_sha)

          rebase_commit = if include_rebase_commit?
            read_and_determine_commit(base_repository, potential_rebase_commit_sha)
          else
            Entity::Commits::Skipped.new
          end

          priority = begin
            Enums::Priority.deserialize(@priority)
          rescue => exception # rubocop:disable Lint/RescueException
            Enums::Priority::High
          end

          Request.new(
            pull_request_id: @pull.id,
            base_repository_id: base_repository.id,
            head_repository_id: head_repository.id,
            priority:,
            base_branch_sha:,
            head_branch_sha:,
            rebase_commit:,
            merge_commit:,
            database_merge_conflict_record_exists: @pull.conflict.present?,
            database_mergeable_value: @pull.mergeable,
            database_merge_commit_sha_value: @pull.merge_commit_sha,
          )
        end

        sig { returns(Integer) }
        def rebase_timeout
          ENV["REBASE_TIMEOUT_SECONDS"]&.to_i ||
            (FeatureFlag.vexi.enabled_or_raise?(:rebase_timeout_1sec) ? 1 : 7) # rubocop:disable GitHub/FeatureManagement/NoVexiEnabledOrRaiseUsage
        end

        sig { returns(T::Boolean) }
        def include_rebase_commit?
          if GitHub.skip_rebase_commit_generation_from_rebase_merge_settings
            @pull.rebase_merge_allowed?
          else
            !feature_enabled?(:merge_commit_request_skip_rebase_via_api) ||
            @pull.merge_commit_allowed? ||
            @pull.rebase_merge_allowed?
          end
        end

        private

        sig { params(repository: Repository, sha: T.nilable(String)).returns(T.any(Entity::Commits::Found, Entity::Commits::Pending)) }
        def read_and_determine_commit(repository, sha)
          unless commit = commits.read(repository, sha)
            return Entity::Commits::Pending.new
          end

          # Assume everything _could_ be nil.
          commit_sha = T.let(commit.sha, T.nilable(String))
          tree_sha = T.let(commit.tree_oid, T.nilable(String))
          base_sha, head_sha = T.let(commit.parent_oids, T::Array[T.nilable(String)])
          created_at = T.let(commit.created_at, T.nilable(Time))

          # Treat missing commit data as a non-valid commit to be regenerated.
          # TODO: How does this happen? Squash/rebase?
          if base_sha.nil? || commit_sha.nil? || tree_sha.nil? || created_at.nil?
            GitHub.dogstats.increment("merge_commits.create_commits.loader.missing_commit_data")
            return Entity::Commits::Pending.new
          end

          Entity::Commits::Found.new(
            base_sha:,
            head_sha:,
            sha: commit_sha,
            tree_sha:,
            created_at:
          )
        end

        sig { returns(T.nilable(Repository)) }
        def determine_base_repository
          if @repo.advisory_workspace?
            @repo.parent_advisory_repository
          else
            @pull.base_repository
          end
        end

        sig { returns(T.nilable(Repository)) }
        def determine_head_repository
          if @repo.advisory_workspace?
            @repo
          else
            @pull.head_repository
          end
        end

        sig { returns(T.any(Loaders::Refs, GitSystems::BatchReadRefs)) }
        memoize def refs
          if feature_enabled?(:mcr_batch_services)
            GitSystems::BatchReadRefs.new
          else
            Loaders::Refs.new
          end
        end

        sig { returns(T.any(Loaders::Commits, GitSystems::BatchReadCommits)) }
        memoize def commits
          if feature_enabled?(:mcr_batch_services)
            GitSystems::BatchReadCommits.new
          else
            Loaders::Commits.new
          end
        end

        sig { params(base_branch_sha: String, head_branch_sha: String).returns(T::Boolean) }
        def duplicate_merge_commit_request?(base_branch_sha:, head_branch_sha:)
          MergeCommitRequest.where(
            repository_id: @repo.id,
            pull_request_id: @pull.id,
            base_branch_sha:,
            head_branch_sha:,
          ).exists?
        end

        sig { params(feature: Symbol).returns(T::Boolean) }
        def feature_enabled?(feature)
          @repo.feature_flag_enabled?(feature, default: false)
        end

        sig do
          type_parameters(:T)
            .params(name: Symbol, block: T.proc.returns(T.type_parameter(:T)))
            .returns(T.type_parameter(:T))
        end
        def with_telemetry(name, &block)
          GitHub.tracer.in_span("merge_commits.create_commits.loader.#{name}", kind: :internal) do
            GitHub.dogstats.distribution_time("merge_commits.create_commits.loader.duration", tags: ["action:#{name}"], &block)
          end
        end
      end
    end
  end
end
