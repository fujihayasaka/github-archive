# typed: true
# frozen_string_literal: true

require "test_helper"

module PullRequests
  module MergeCommit
    # Enables mocking out side effects requested by the processor. Mock results can be given to the initializer
    # as an array of results, allowing sequential calls with different outcomes.
    class MockCommand
      include ICommand

      module Assertions
        extend T::Helpers

        requires_ancestor { GitHub::TestCase }

        sig { params(command: MockCommand, actions: T::Array[T.any(T::Array[MockCommand::Action], MockCommand::Action)]).void }
        def assert_actions_performed(command, actions)
          assert_equal actions.flatten, command.actions
        end

        sig { params(strings: T::Array[String]).returns(T::Array[String]) }
        def sanitize_actions(strings)
          strings.each do
            _1.gsub!("data PullRequests::MergeCommit::MockCommand::", "")
          end
        end

        sig do
          params(
            request: CreateCommits::Request,
            merge_sha: T.nilable(String),
            merge_state: Enums::CommitState,
            merge_conflict: T.untyped,
            rebase_sha: T.nilable(String),
            rebase_state: Enums::CommitState,
            rebase_conflict: T.untyped,
            requested_at: Time,
          ).returns(MockCommand::InsertMergeCommitRequest)
        end
        def did_insert_merge_commit_request(request, merge_sha:, merge_state:, merge_conflict:, rebase_sha:, rebase_state:, rebase_conflict:, requested_at: Time.now)
          MockCommand::InsertMergeCommitRequest.new(
            request.pull_request_id,
            request.priority,
            request.base_repository_id,
            request.head_repository_id,
            request.base_branch_sha,
            request.head_branch_sha,
            merge_sha,
            merge_state,
            merge_conflict,
            rebase_sha,
            rebase_state,
            rebase_conflict,
            requested_at,
          )
        end

        sig { params(request: IRequest).returns(MockCommand::EnqueueBatchRefUpdatesJob) }
        def did_enqueue_batch_ref_updates_job(request)
          MockCommand::EnqueueBatchRefUpdatesJob.new(request.pull_request_id)
        end

        sig { params(requests: IRequest).returns(MockCommand::TransitionToProcessing) }
        def did_mark_as_processing(*requests)
          MockCommand::TransitionToProcessing.new(requests.map(&:pull_request_id))
        end

        sig { params(updates: ICommand::RefUpdate).returns(MockCommand::UpdateRefs) }
        def did_update_refs(*updates)
          MockCommand::UpdateRefs.new(updates.map(&:serialize))
        end

        sig { params(requests: IRequest).returns(MockCommand::MarkPullRequestAsMergeable) }
        def did_mark_pull_as_mergeable(*requests)
          MockCommand::MarkPullRequestAsMergeable.new(requests.map(&:pull_request_id))
        end

        sig { params(requests: IRequest).returns(MockCommand::MarkPullRequestAsUnmergeable) }
        def did_mark_pull_as_unmergeable(*requests)
          MockCommand::MarkPullRequestAsUnmergeable.new(requests.map(&:pull_request_id))
        end

        sig { params(requests: IRequest).returns(MockCommand::DispatchMergeabilityEvent) }
        def did_dispatch_pull_mergeability_event(*requests)
          MockCommand::DispatchMergeabilityEvent.new(requests.map(&:pull_request_id))
        end

        sig { params(requests: IRequest).returns(MockCommand::DeleteProcessingRequests) }
        def did_delete_requests(*requests)
          MockCommand::DeleteProcessingRequests.new(requests.map(&:pull_request_id))
        end

        sig { params(request: IRequest, base_sha: String, head_sha: String, attempts: Integer).returns(T::Array[MockCommand::CreateMergeCommit]) }
        def did_create_merge_commit(request, base_sha:, head_sha:, attempts: 1)
          attempts.times.map { MockCommand::CreateMergeCommit.new(request.pull_request_id, base_sha, head_sha) }
        end

        sig { params(request: IRequest, base_sha: String, merge_commit_sha: String, attempts: Integer).returns(T::Array[MockCommand::CreateRebaseCommit]) }
        def did_create_rebase_commit(request, base_sha:, merge_commit_sha:, attempts: 1)
          attempts.times.map { MockCommand::CreateRebaseCommit.new(request.pull_request_id, base_sha, merge_commit_sha) }
        end

        sig { params(request: IRequest, type: Enums::Conflict, conflict: T.untyped).returns(MockCommand::StoreConflicts) }
        def did_store_conflicts(request, type:, conflict:)
          MockCommand::StoreConflicts.new(request.pull_request_id, type, conflict)
        end

        sig { params(request: IRequest, type: Enums::Conflict).returns(MockCommand::ClearConflicts) }
        def did_clear_conflicts(request, type:)
          MockCommand::ClearConflicts.new(request.pull_request_id, type)
        end
      end

      sig do
        params(
          insert_merge_commit_request: T::Array[ICommand::InsertMergeCommitRequestResult],
          enqueue_batch_ref_updates_job: T::Array[ICommand::EnqueueBatchRefUpdatesJobResult],
          transition_to_processing: T::Array[ICommand::TransitionToProcessingResult],
          create_merge_commit: T::Array[ICommand::CreateMergeCommitResult],
          create_rebase_commit: T::Array[ICommand::CreateRebaseCommitResult],
          update_refs: T::Array[ICommand::UpdateRefsResult],
          mark_pull_request_as_mergeable: T::Array[ICommand::MarkPullRequestAsMergeableResult],
          mark_pull_request_as_unmergeable: T::Array[ICommand::MarkPullRequestAsUnmergeableResult],
          store_conflicts: T::Array[ICommand::GenericResult],
          clear_mergeability: T::Array[ICommand::ClearMergeabilityResult],
          delete_processing_requests: T::Array[ICommand::DeleteProcessingRequestsResult],
        ).void
      end
      def initialize(
        insert_merge_commit_request: [],
        enqueue_batch_ref_updates_job: [],
        transition_to_processing: [],
        create_merge_commit: [],
        create_rebase_commit: [],
        update_refs: [],
        mark_pull_request_as_mergeable: [],
        mark_pull_request_as_unmergeable: [],
        store_conflicts: [],
        clear_mergeability: [],
        delete_processing_requests: []
      )
        @actions = T.let([], Actions)
        @insert_merge_commit_request_results = insert_merge_commit_request
        @enqueue_batch_ref_updates_job_results = enqueue_batch_ref_updates_job
        @transition_to_processing_results = transition_to_processing
        @create_merge_commit_results = create_merge_commit
        @create_rebase_commit_results = create_rebase_commit
        @update_refs_results = update_refs
        @mark_pull_request_as_mergeable = mark_pull_request_as_mergeable
        @mark_pull_request_as_unmergeable = mark_pull_request_as_unmergeable
        @store_conflicts = store_conflicts
        @clear_mergeability = clear_mergeability
        @delete_processing_requests = delete_processing_requests
      end

      InsertMergeCommitRequest = Data.define(
        :pull_request_id, :priority, :base_repository_id, :head_repository_id, :base_branch_sha, :head_branch_sha,
        :merge_commit_sha, :merge_commit_state, :merge_commit_conflict,
        :rebase_commit_sha, :rebase_commit_state, :rebase_commit_conflict, :requested_at
      )
      sig do
        override.params(
          pull_request_id: Integer,
          priority: Enums::Priority,
          base_repository_id: Integer,
          head_repository_id: Integer,
          base_branch_sha: String,
          head_branch_sha: String,
          merge_sha: T.nilable(String),
          merge_state: MergeState,
          merge_conflict: T.nilable(T::Hash[T.untyped, T.untyped]),
          rebase_sha: T.nilable(String),
          rebase_state: RebaseState,
          rebase_conflict: T.nilable(T::Hash[T.untyped, T.untyped]),
          requested_at: Time,
        ).returns(InsertMergeCommitRequestResult)
      end
      def insert_merge_commit_request!(
        pull_request_id:,
        priority:,
        base_repository_id:,
        head_repository_id:,
        base_branch_sha:,
        head_branch_sha:,
        merge_sha:,
        merge_state:,
        merge_conflict:,
        rebase_sha:,
        rebase_state:,
        rebase_conflict:,
        requested_at:
      )
        @actions << InsertMergeCommitRequest.new(
          pull_request_id, priority, base_repository_id, head_repository_id,
          base_branch_sha, head_branch_sha,
          merge_sha, merge_state, merge_conflict,
          rebase_sha, rebase_state, rebase_conflict,
          requested_at,
        )

        @insert_merge_commit_request_results.shift || ICommand::Result::Success.new
      end

      EnqueueBatchRefUpdatesJob = Data.define(:pull_request_id)
      sig { override.params(pull_request_id: Integer).returns(EnqueueBatchRefUpdatesJobResult) }
      def enqueue_batch_ref_updates_job!(pull_request_id:)
        @actions << EnqueueBatchRefUpdatesJob.new(pull_request_id)
        @enqueue_batch_ref_updates_job_results.shift || ICommand::Result::Success.new
      end

      TransitionToProcessing = Data.define(:ids)
      sig { override.params(pull_request_ids: T::Array[Integer]).returns(TransitionToProcessingResult) }
      def transition_to_processing!(pull_request_ids:)
        @actions << TransitionToProcessing.new(pull_request_ids)
        @transition_to_processing_results.shift || ICommand::Result::Success.new
      end

      TransitionInvalidRequestToMergeable = Data.define(:ids)
      sig { override.params(pull_request_id: Integer).returns(TransitionInvalidRequestToMergeableResult) }
      def transition_invalid_request_to_mergeable!(pull_request_id:)
        @actions << TransitionInvalidRequestToMergeable.new([pull_request_id])
        ICommand::Result::Success.new
      end

      CreateMergeCommit = Data.define(:id, :base_sha, :head_sha)
      sig { override.params(pull_request_id: Integer, head_sha: String, base_sha: String).returns(CreateMergeCommitResult) }
      def create_merge_commit!(pull_request_id:, head_sha:, base_sha:)
        @actions << CreateMergeCommit.new(pull_request_id, base_sha, head_sha)
        @create_merge_commit_results.shift || PullRequests::GitSystems::Commit::Created.new(
          sha: SecureRandom.hex(16),
          base_sha:,
          head_sha:,
        )
      end

      CreateRebaseCommit = Data.define(:id, :base_sha, :merge_commit_sha)
      sig { override.params(pull_request_id: Integer, base_sha: String, merge_commit_sha: String, timeout: Integer).returns(CreateRebaseCommitResult) }
      def create_rebase_commit!(pull_request_id:, base_sha:, merge_commit_sha:, timeout:)
        @actions << CreateRebaseCommit.new(pull_request_id, base_sha, merge_commit_sha)
        @create_rebase_commit_results.shift || PullRequests::GitSystems::Commit::Created.new(
          sha: SecureRandom.hex(16),
          base_sha:,
          head_sha: merge_commit_sha,
        )
      end

      UpdateRefs = Data.define(:updates)
      sig { override.params(updates: T::Array[ICommand::RefUpdate]).returns(UpdateRefsResult) }
      def update_refs!(updates:)
        @actions << UpdateRefs.new(updates.map(&:serialize))
        @update_refs_results.shift || ICommand::Result::Success.new
      end

      MarkPullRequestAsMergeable = Data.define(:ids)
      sig { override.params(pull_request_id: Integer, merge_commit_sha: String).returns(MarkPullRequestAsMergeableResult) }
      def mark_pull_request_as_mergeable!(pull_request_id:, merge_commit_sha:)
        @actions << MarkPullRequestAsMergeable.new([pull_request_id])
        @mark_pull_request_as_mergeable.shift || ICommand::Result::Success.new
      end

      MarkPullRequestAsUnmergeable = Data.define(:ids)
      sig { override.params(pull_request_id: Integer).returns(MarkPullRequestAsUnmergeableResult) }
      def mark_pull_request_as_unmergeable!(pull_request_id:)
        @actions << MarkPullRequestAsUnmergeable.new([pull_request_id])
        @mark_pull_request_as_unmergeable.shift || ICommand::Result::Success.new
      end

      StoreConflicts = Data.define(:id, :type, :details)
      sig do
        override.params(
          pull_request_id: Integer,
          details: T::Hash[T.untyped, T.untyped],
          type: Enums::Conflict
        ).returns(GenericResult)
      end
      def store_conflicts!(pull_request_id:, details:, type:)
        @actions << StoreConflicts.new(pull_request_id, type, details)
        @store_conflicts.shift || ICommand::Result::Success.new
      end

      ClearConflicts = Data.define(:id, :type)
      sig { override.params(pull_request_id: Integer, type: Enums::Conflict).returns(GenericResult) }
      def clear_conflicts!(pull_request_id:, type:)
        @actions << ClearConflicts.new(pull_request_id, type)
        @store_conflicts.shift || ICommand::Result::Success.new
      end

      ClearMergeability = Data.define(:ids)
      sig { override.params(pull_request_id: Integer).returns(ClearMergeabilityResult) }
      def clear_mergeability!(pull_request_id:)
        @actions << ClearMergeability.new([pull_request_id])
        @clear_mergeability.shift || ICommand::Result::Success.new
      end

      DeleteProcessingRequests = Data.define(:ids)
      sig { override.params(pull_request_ids: T::Array[Integer]).returns(DeleteProcessingRequestsResult) }
      def delete_processing_requests!(pull_request_ids:)
        @actions << DeleteProcessingRequests.new(pull_request_ids)
        @delete_processing_requests.shift || ICommand::Result::Success.new
      end

      DispatchMergeabilityEvent = Data.define(:ids)
      sig { override.params(pull_request_id: Integer).returns(DispatchMergabilityResult) }
      def dispatch_mergeability_event!(pull_request_id:)
        @actions << DispatchMergeabilityEvent.new([pull_request_id])
        ICommand::Result::Success.new
      end

      sig { override.params(name: Symbol).returns(T::Boolean) }
      def feature_enabled?(name)
        GitHub.flipper[name].enabled?
      end

      Action = T.type_alias do
        T.any(
          InsertMergeCommitRequest,
          EnqueueBatchRefUpdatesJob,
          TransitionToProcessing,
          CreateMergeCommit,
          CreateRebaseCommit,
          UpdateRefs,
          MarkPullRequestAsMergeable,
          MarkPullRequestAsUnmergeable,
          StoreConflicts,
          ClearConflicts,
          ClearMergeability,
          DeleteProcessingRequests,
          DispatchMergeabilityEvent,
          TransitionInvalidRequestToMergeable
        )
      end

      Actions = T.type_alias { T::Array[Action] }

      sig { returns(Actions) }
      attr_reader :actions
    end
  end
end
