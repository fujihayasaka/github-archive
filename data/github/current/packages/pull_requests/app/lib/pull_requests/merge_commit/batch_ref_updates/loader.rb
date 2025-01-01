# typed: strict
# frozen_string_literal: true

module PullRequests
  module MergeCommit
    module BatchRefUpdates
      # Perform the bulk of the read operations on our dependencies in a single location. Ensure we're performing as many
      # batch operations as possible.
      class Loader
        include GitHub::Memoizer

        sig { params(repository: Repository, batch_size: Integer).void }
        def initialize(repository:, batch_size:)
          @repository = repository
          @batch_size = batch_size
        end

        # PullRequests needing merge commits created.
        sig { returns(T::Array[PullRequest]) }
        memoize def pull_requests
          with_telemetry(:pull_requests) do
            return [] if merge_commit_requests.empty?

            models = PullRequest
              .includes(:user, :conflict)
              .where(
                repository: @repository,
                id: merge_commit_requests.map(&:pull_request_id).compact.uniq
              ).to_a

            # We default to reading from the primary for the issues-pull-requests
            # cluster. For `PullRequest` and `MergeCommitRequest` records it's
            # important to have the freshest data, but for `Issue` we can afford
            # a little replication lag, so we use a replica to load those records.
            ActiveRecord::Base.connected_to(role: :reading) do
              GitHub::PrefillAssociations.prefill_associations(models, [:issue])
            end

            models
          end
        end

        # PullRequests needing merge commits created.
        sig { returns(T::Array[Repository]) }
        memoize def repositories
          with_telemetry(:repositories) do
            collection = [@repository]

            # Determine all the ids to load, excluding the already loaded @repository.
            ids = T.let(
              merge_commit_requests \
                .pluck(:repository_id, :head_repository_id, :base_repository_id)
                .flatten
                .uniq
                .without(@repository.id),
              T::Array[Integer]
            )

            # Using read replicas, load all the missing Repositories IDs, and append them to the array.
            if ids.any?
              ActiveRecord::Base.connected_to(role: :reading) do
                collection.concat(
                  Repositories::Public.load_repositories(ids).to_a
                )
              end
            end

            collection
          end
        end

        # Load without ActiveRecord models the pull requests and their state for the current run.
        sig { returns(T::Array[MergeCommitRequest]) }
        memoize def merge_commit_requests
          with_telemetry(:merge_commit_requests) do
            MergeCommitRequest
              .where(repository_id: @repository.id)
              .order("created_at ASC")
              .limit(@batch_size)
              .to_a
          end
        end

        sig { returns(T::Array[Integer]) }
        def pull_request_ids
          merge_commit_requests.map(&:pull_request_id).compact
        end

        # Builds the collection of Request structures describing the Pull Request to be updated.
        sig { returns([T::Array[Request], T::Array[Request::Invalid]]) }
        memoize def requests
          with_telemetry(:requests) do
            requests = T.let([], T::Array[Request])
            invalid_requests = T.let([], T::Array[Request::Invalid])

            return [requests, invalid_requests] if merge_commit_requests.empty?

            build_requests.each do |built_request|
              case built_request
              when Request
                requests << built_request
              when Request::Invalid
                invalid_requests << built_request
              else
                T.absurd(built_request)
              end
            end

            [requests, invalid_requests]
          end
        end

        sig { returns(T::Array[T.any(Request, Request::Invalid)]) }
        def build_requests
          requests = T.let([], T::Array[T.any(Request, Request::Invalid)])

          # Collection of type-asserted and valid database models.
          #   [uuid, merge_commit_request, pull_request, repository, base_repository, head_repository]
          eligible_requests = T.let([], T::Array[[String, MergeCommitRequest, PullRequest, Repository, Repository, Repository]])

          # First pass to filter out Pulls we know can't ever be processed.
          merge_commit_requests.each do |merge_commit_request|
            unless pull = pull_requests.find { _1.id == merge_commit_request.pull_request_id }
              next requests << Request::Invalid.new(reason: Reason::MissingPullRequest, merge_commit_request:)
            end

            unless pull.issue
              next requests << Request::Invalid.new(reason: Reason::MissingIssue, merge_commit_request:)
            end

            # Ignore duplicate requests for PRs.
            if eligible_requests.any? { |(_, _, pull_request, _)| pull_request == pull }
              next requests << Request::Invalid.new(reason: Reason::DuplicateRequest, merge_commit_request:)
            end

            if pull.merged_at? || pull.closed?
              next requests << Request::Invalid.new(reason: Reason::ClosedOrMerged, merge_commit_request:)
            end

            unless repository = repositories.find { _1.id == merge_commit_request.repository_id }
              next requests << Request::Invalid.new(reason: Reason::MissingRepository, merge_commit_request:)
            end

            unless base_repository = repositories.find { _1.id == merge_commit_request.base_repository_id }
              next requests << Request::Invalid.new(reason: Reason::MissingBaseRepository, merge_commit_request:)
            end

            unless head_repository = repositories.find { _1.id == merge_commit_request.head_repository_id }
              next requests << Request::Invalid.new(reason: Reason::MissingHeadRepository, merge_commit_request:)
            end

            # Unique identifier so that we can do equality operations without deleting duplicate requests.
            identifier = SecureRandom.hex(6)

            eligible_requests << [identifier, merge_commit_request, pull, repository, base_repository, head_repository]

            refs.request(base_repository, pull.qualified_base_ref_name)
            refs.request(head_repository, pull.qualified_head_ref_name)
          end

          with_telemetry(:refs) { refs.execute }

          # Clone the Array so we can mutate it while looping through and not causing issues in the each loop.
          eligible_requests.clone.each do |tuple|
            _, merge_commit_request, pull, repository, base_repository, head_repository = tuple

            if merge_commit_request.base_branch_sha != refs.read(base_repository, pull.qualified_base_ref_name)
              eligible_requests.delete(tuple)
              next requests << Request::Invalid.new(reason: Reason::BaseBranchPushed, merge_commit_request:)
            end

            if merge_commit_request.head_branch_sha != refs.read(head_repository, pull.qualified_head_ref_name)
              eligible_requests.delete(tuple)
              next requests << Request::Invalid.new(reason: Reason::HeadBranchPushed, merge_commit_request:)
            end

            commits.request(repository, merge_commit_request.merge_sha)
            commits.request(repository, merge_commit_request.rebase_sha)
          end

          with_telemetry(:commits) { commits.execute }

          eligible_requests.each do |(_, merge_commit_request, pull, repository)|
            case merge_commit = deserialize_merge_commit(merge_commit_request:, repository:)
            when Reason
              next requests << Request::Invalid.new(reason: merge_commit, merge_commit_request:)
            end

            case rebase_commit = deserialize_rebase_commit(merge_commit_request:, repository:)
            when Reason
              next requests << Request::Invalid.new(reason: rebase_commit, merge_commit_request: merge_commit_request)
            end

            requests << Request.new(
              pull_request_id: merge_commit_request.pull_request_id.to_i,
              database_mergeable_value: pull.mergeable,
              database_merge_commit_sha_value: pull.merge_commit_sha,
              database_merge_conflict_record_exists: pull.conflict.present?,
              database_rebase_conflict_record_exists: pull.rebase_conflict.present?,
              merge_refname: pull.merge_ref,
              merge_commit: merge_commit,
              rebase_refname: pull.rebase_ref,
              rebase_commit: rebase_commit,
              requested_at: merge_commit_request.requested_at.utc
            )
          end

          requests
        end

        private

        # Short hand alias to reduce noise.
        Reason = Enums::InvalidRequestReason

        sig { params(name: Symbol).returns(T::Boolean) }
        def feature_enabled?(name)
          @repository.feature_enabled?(name)
        end

        sig do
          type_parameters(:T)
            .params(name: Symbol, block: T.proc.returns(T.type_parameter(:T)))
            .returns(T.type_parameter(:T))
        end
        def with_telemetry(name, &block)
          GitHub.tracer.in_span("merge_commits.batch_ref_updates.loader.#{name}", kind: :internal) do
            GitHub.dogstats.distribution_time("merge_commits.batch_ref_updates.loader.duration", tags: ["action:#{name}"], &block)
          end
        end

        sig { returns(Loaders::Commits) }
        memoize def commits
          Loaders::Commits.new
        end

        sig { returns(Loaders::Refs) }
        memoize def refs
          Loaders::Refs.new
        end

        sig { params(merge_commit_request: MergeCommitRequest, repository: Repository).returns(T.any(Request::MergeCommit, Reason)) }
        def deserialize_merge_commit(merge_commit_request:, repository:)
          case merge_commit = deserialize_commit(
            state: merge_commit_request.merge_state,
            sha: merge_commit_request.merge_sha,
            conflict: merge_commit_request.merge_conflict,
            commit: commits.read(repository, merge_commit_request.merge_sha)
          )
          # These are invalid states it shouldn't ever be in. If they are, invalidate them.
          when Entity::Commits::Skipped, Entity::Commits::Ineligible
            Reason::InvalidCommitState
          else
            merge_commit
          end
        end

        sig { params(merge_commit_request: MergeCommitRequest, repository: Repository).returns(T.any(Request::RebaseCommit, Reason)) }
        def deserialize_rebase_commit(merge_commit_request:, repository:)
          deserialize_commit(
            state: merge_commit_request.rebase_state,
            sha: merge_commit_request.rebase_sha,
            conflict: merge_commit_request.rebase_conflict,
            commit: commits.read(repository, merge_commit_request.rebase_sha)
          )
        end

        sig { params(state: String, sha: T.nilable(String), conflict: (T.untyped), commit: T.nilable(::Commit)).returns(T.any(Request::RebaseCommit, Reason)) }
        def deserialize_commit(state:, sha:, conflict:, commit:)
          begin
            state = Enums::CommitState.deserialize(state)
          rescue KeyError
            return Reason::InvalidCommitState
          end

          case state
          when Enums::CommitState::Conflict
            return Entity::Commits::Conflict.new(details: conflict || {})
          when Enums::CommitState::Skipped
            return Entity::Commits::Skipped.new
          when Enums::CommitState::Failed
            return Entity::Commits::Failed.new
          when Enums::CommitState::Ineligible
            return Entity::Commits::Ineligible.new
          end

          if sha.nil?
            return Reason::MissingShaFromDB
          elsif commit.nil?
            return Reason::MissingCommitFromGit
          end

          case state
          when Enums::CommitState::Created
            Entity::Commits::Created.new(sha:)
          when Enums::CommitState::Reused
            Entity::Commits::Reused.new(sha:)
          else T.absurd(state)
          end
        end
      end
    end
  end
end
