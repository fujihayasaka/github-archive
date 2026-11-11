# typed: strict
# frozen_string_literal: true

module PullRequests
  module GitSystems
    # Creates a single squash commit on top of `parent` with the given
    # `tree_oid`, and notifies downstream consumers about the new commit
    # (either via the AuthenticCommits push job or the legacy Hydro
    # `CommitsCreated` event, gated by `:git_commits_via_push_job`).
    class CreateSquashCommit
      sig do
        params(
          repository: Repository,
          parent: String,
          tree_oid: String,
          original_head_oid: String,
          author: T::Hash[Symbol, T.untyped],
          committer: T::Hash[Symbol, T.untyped],
          message: String,
          sign: T::Boolean,
        ).void
      end
      def initialize(repository:, parent:, tree_oid:, original_head_oid:, author:, committer:, message:, sign:)
        # `original_head_oid` is not used when computing the squash commit
        # (the squash is built from `tree_oid` on top of `parent`). It is
        # only carried through so the returned `Commit::Created` can report
        # which PR head this squash represents (i.e. the "head sha" of the
        # source merge commit).
        @original_head_oid = original_head_oid
        @parent = parent
        @tree_oid = tree_oid
        @author = author
        @committer = committer
        @message = message
        @sign = sign
        @repository = repository
      end

      sig { returns(T.any(Commit::Created, Commit::Failed, Commit::Error)) }
      def call
        response = @repository.spokes_api.with_transaction do
          @repository.spokes_api.create_commit(
            tree_oid: @tree_oid,
            author: @author,
            committer: @committer,
            parents: [@parent],
            message: @message,
            sign: @sign,
            cleanup_mode: :CLEANUP_MODE_VERBATIM,
          )
        end

        if sha = response.oid&.id
          notify_commit_created(sha)
          Commit::Created.new(sha:, head_sha: @original_head_oid, base_sha: @parent)
        else
          Commit::Failed.new(code: :not_created)
        end
      rescue SpokesAPI::Error => exception
        Commit::Error.new(exception:)
      end

      private

      sig { params(sha: String).void }
      def notify_commit_created(sha)
        if FeatureFlag.vexi.enabled?(:git_commits_via_push_job, @repository, default: false)
          AuthenticCommits::CommitContext.push_single(sha)
        else
          publish_commits_created_event(sha)
        end
      end

      sig { params(sha: String).void }
      def publish_commits_created_event(sha)
        DatabaseSelector::LastOperations.with_static_replication_state({}) do
          GitHub.aqueduct_fallback_hydro_publisher.publish(
            {
              repository_id: @repository.id,
              request_context: Hydro::EntitySerializer.request_context(GitHub.context.to_hash),
              created_at: Time.now,
              commit_shas: [sha],
              enabled_flags: Repositories::HydroPushJobFlags.enabled_for_repo(@repository),
            },
            schema: "github.repositories.v1.CommitsCreated",
            partition_key: @repository.id,
          )
        end
      end
    end
  end
end
