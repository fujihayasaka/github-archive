# typed: strict
# frozen_string_literal: true

module PullRequests
  module MergeCommit
    module CreateCommits
      class Loader
        extend T::Sig
        include Enums
        include GitHub::Memoizer

        sig { params(pull_request: PullRequest, repository: Repository).void }
        def initialize(pull_request:, repository:)
          @pull = pull_request
          @repo = repository # Note that requiring repository here requires the caller to handle InvalidRequestReason::MissingRepository
        end

        sig { returns(T.any(Request, InvalidRequestReason)) }
        memoize def request
          if @pull.merged_at? || @pull.closed?
            return InvalidRequestReason::ClosedOrMerged
          end

          unless base_repository = determine_base_repository
            return InvalidRequestReason::MissingBaseRepository
          end
          unless head_repository = determine_head_repository
            return InvalidRequestReason::MissingHeadRepository
          end

          base_ref_name = @pull.qualified_base_ref_name
          head_ref_name = @pull.qualified_head_ref_name
          rebase_ref_name = @pull.rebase_ref
          merge_commit_sha = @pull.merge_commit_sha

          refs.request(base_repository, base_ref_name)
          refs.request(head_repository, head_ref_name)
          if include_rebase_commit?
            refs.request(base_repository, rebase_ref_name)
          end
          refs.execute

          commits.request(base_repository, merge_commit_sha)
          if include_rebase_commit?
            potential_rebase_commit_sha = refs.read(base_repository, rebase_ref_name)
            commits.request(base_repository, potential_rebase_commit_sha)
          end
          commits.execute

          unless base_branch_sha = refs.read(base_repository, base_ref_name)
            return InvalidRequestReason::MissingBaseBranchSha
          end
          unless head_branch_sha = refs.read(head_repository, head_ref_name)
            return InvalidRequestReason::MissingHeadBranchSha
          end

          merge_commit = if commit = commits.read(base_repository, merge_commit_sha)
            base_sha, head_sha = commit.parent_oids
            Entity::Commits::Found.new(sha: commit.sha, base_sha:, head_sha:)
          else
            Entity::Commits::Pending.new
          end

          rebase_commit = if include_rebase_commit?
            # TODO: reimplement as part of refactor in https://github.com/github/pull-requests/issues/13398
            # if commit = commits.read(base_repository, potential_rebase_commit_sha)
            #   Entity::Commits::Found.new(sha: commit.sha, base_sha: base_branch_sha, head_sha: T.must(merge_commit_sha))
            # else
            Entity::Commits::Pending.new
            # end
          else
            Entity::Commits::Skipped.new
          end

          Request.new(
            priority: Enums::Priority::High,
            pull_request_id: T.must(@pull.id),
            base_repository_id: T.must(base_repository.id),
            head_repository_id: T.must(head_repository.id),
            base_branch_sha:,
            head_branch_sha:,
            rebase_commit:,
            merge_commit:,
            database_merge_conflict_record_exists: @pull.conflict.present?,
            database_mergeable_value: @pull.mergeable,
            database_merge_commit_sha_value: @pull.merge_commit_sha,
          )
        end

        sig { returns(Numeric) }
        def rebase_timeout
          ENV["REBASE_TIMEOUT_SECONDS"]&.to_i ||
            (GitHub.flipper[:rebase_timeout_1sec].enabled? ? 1 : 7)
        end

        sig { returns(T::Boolean) }
        def include_rebase_commit?
          !@repo.feature_enabled?(:merge_commit_request_skip_rebase_via_api) ||
          @repo.merge_commit_allowed? ||
          @repo.rebase_merge_allowed?
        end

        private

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

        sig { returns(Loaders::Refs) }
        memoize def refs
          Loaders::Refs.new
        end

        sig { returns(Loaders::Commits) }
        memoize def commits
          Loaders::Commits.new
        end
      end
    end
  end
end
