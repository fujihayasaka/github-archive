# typed: true
# frozen_string_literal: true

require "test_helper"

module PullRequests
  module MergeCommit
    class ProcessorTest < GitHub::TestCase
      test "creating the merge commit for a single PR" do
        configuration = Configuration.new(skip_rebase: false)

        merge_commit_sha = "ABCDE12345"
        merge_commit_head_sha = "whimsy"
        merge_commit_base_sha = "whimsically"
        rebase_commit_sha = "54321EDCBA"
        pull_request_number = 1

        valid_request = build_request(pull_request_number:)
        invalid_request = Request::Invalid.new(
          reason: Request::Invalid::Reason::MissingPullRequest,
          pull_request_id: pull_request_number + 1,
          pull_request_number: pull_request_number + 1,
        )

        command = MockCommand.new(
          create_merge_commit: [
            GitSystems::Commit::Created.new(
              sha: merge_commit_sha,
              base_sha: T.must(valid_request.base_ref_sha),
              head_sha: T.must(valid_request.head_ref_sha),
            )
          ],
          create_rebase_commit: [
            GitSystems::Commit::Created.new(
              sha: rebase_commit_sha,
              base_sha: T.must(valid_request.base_ref_sha),
              head_sha: merge_commit_sha,
            )
          ]
        )

        result = Processor.new(
          requests: [valid_request],
          command:,
          configuration:,
          invalid_requests: [invalid_request],
        ).call

        assert_instance_of GitSystems::Commit::Created, valid_request.merge_commit
        assert_instance_of GitSystems::Commit::Created, valid_request.rebase_commit
        assert_equal Request::Mergeability::Mergeable, valid_request.current_mergeability

        assert_equal [
          MockCommand::TransitionToProcessing.new([valid_request.pull_request_id, invalid_request.pull_request_id]),
          MockCommand::CreateMergeCommit.new([pull_request_number]),
          MockCommand::CreateRebaseCommit.new([pull_request_number], merge_commit_sha, configuration.rebase_timeout),
          MockCommand::UpdateRefs.new([
            ICommand::RefUpdate.new(name: valid_request.merge_ref_name, sha: merge_commit_sha, pull_request_id: pull_request_number),
            ICommand::RefUpdate.new(name: valid_request.rebase_ref_name, sha: rebase_commit_sha, pull_request_id: pull_request_number),
          ]),
          MockCommand::MarkPullRequestAsMergeable.new([pull_request_number]),
          MockCommand::DispatchMergeabilityEvent.new([pull_request_number]),
          MockCommand::DeleteProcessingRequests.new([valid_request.pull_request_id, invalid_request.pull_request_id]),
        ].inspect, command.actions.inspect
      end

      test "creating the merge commit for a single PR without rebase" do
        configuration = Configuration.new(skip_rebase: true)

        pull_request_number = 1

        request = build_request(pull_request_number:)

        merge_commit_sha = "ABCDE12345"
        command = MockCommand.new(
          create_merge_commit: [
            GitSystems::Commit::Created.new(
              sha: merge_commit_sha,
              base_sha: T.must(request.base_ref_sha),
              head_sha: T.must(request.head_ref_sha),
            )
          ]
        )

        result = Processor.new(
          requests: [request],
          command:,
          configuration:,
          invalid_requests: [],
        ).call

        assert_instance_of GitSystems::Commit::Created, request.merge_commit
        assert_instance_of Request::Commits::Skipped, request.rebase_commit
        assert_equal Request::Mergeability::Mergeable, request.current_mergeability

        assert_equal [
          MockCommand::TransitionToProcessing.new([pull_request_number]),
          MockCommand::CreateMergeCommit.new([pull_request_number]),
          MockCommand::UpdateRefs.new([
            ICommand::RefUpdate.new(name: request.merge_ref_name, sha: merge_commit_sha, pull_request_id: request.pull_request_number),
            ICommand::RefUpdate.new(name: request.rebase_ref_name, sha: GitHub::NULL_OID, pull_request_id: pull_request_number),
          ]),
          MockCommand::MarkPullRequestAsMergeable.new([pull_request_number]),
          MockCommand::DispatchMergeabilityEvent.new([pull_request_number]),
          MockCommand::DeleteProcessingRequests.new([pull_request_number]),
        ].inspect, command.actions.inspect
      end

      test "valid merge commit but missing mergeable transitions it to mergeable" do
        configuration = Configuration.new(skip_rebase: true)

        command = MockCommand.new

        pull_request_number = 1

        invalid_request = Request::Invalid.new(
          reason: Request::Invalid::Reason::IndeterminateAndUpToDate,
          pull_request_id: pull_request_number,
          pull_request_number: pull_request_number,
        )

        result = Processor.new(
          requests: [],
          command:,
          configuration:,
          invalid_requests: [invalid_request],
        ).call

        assert_equal [
          MockCommand::TransitionToProcessing.new([pull_request_number]),
          MockCommand::TransitionInvalidRequestToMergeable.new([pull_request_number]),
          MockCommand::DeleteProcessingRequests.new([pull_request_number]),
        ], command.actions
      end

      test "merge conflict marks pull as unmergeable" do
        configuration = Configuration.new(skip_rebase: false)

        pull_request_number = 1

        request = build_request(pull_request_number:)

        command = MockCommand.new(
          create_merge_commit: [GitSystems::Commit::Conflict.new]
        )

        result = Processor.new(
          requests: [request],
          command:,
          configuration:,
          invalid_requests: [],
        ).call

        assert_instance_of GitSystems::Commit::Conflict, request.merge_commit
        assert_equal Request::Mergeability::Conflict, request.current_mergeability

        assert_actions_performed command.actions, [
          MockCommand::TransitionToProcessing.new([pull_request_number]),
          MockCommand::CreateMergeCommit.new([pull_request_number]),
          MockCommand::MarkPullRequestAsUnmergeable.new([pull_request_number]),
          MockCommand::DispatchMergeabilityEvent.new([pull_request_number]),
          MockCommand::DeleteProcessingRequests.new([pull_request_number]),
        ]
      end

      test "mergability events are not dispatched for duplicate conflicts" do
        configuration = Configuration.new(skip_rebase: false)

        pull_request_number = 1

        request = build_request(
          pull_request_number:,
          previous_mergeability: Request::Mergeability::Conflict
        )

        command = MockCommand.new(
          create_merge_commit: [GitSystems::Commit::Conflict.new]
        )

        result = Processor.new(
          requests: [request],
          command:,
          configuration:,
          invalid_requests: [],
        ).call

        assert_instance_of GitSystems::Commit::Conflict, request.merge_commit
        assert_equal Request::Mergeability::Conflict, request.current_mergeability

        assert_actions_performed command.actions, [
          MockCommand::TransitionToProcessing.new([pull_request_number]),
          MockCommand::CreateMergeCommit.new([pull_request_number]),
          MockCommand::MarkPullRequestAsUnmergeable.new([pull_request_number]),
          MockCommand::DeleteProcessingRequests.new([pull_request_number]),
        ]
      end

      test "failing to create a merge commit automatically skips the rebase commit" do
        configuration = Configuration.new(skip_rebase: false)

        command = MockCommand.new(
          create_merge_commit: [
            GitSystems::Commit::Failed.new(code: :unknown),
          ]
        )

        request = build_request

        result = Processor.new(
          requests: [request],
          command:,
          configuration:,
          invalid_requests: [],
        ).call

        assert_instance_of GitSystems::Commit::Failed, request.merge_commit
        assert_instance_of Request::Commits::Skipped, request.rebase_commit
        assert_equal Request::Mergeability::Indeterminate, request.current_mergeability

        assert_equal command.actions, [
          MockCommand::TransitionToProcessing.new([request.pull_request_number]),
          MockCommand::CreateMergeCommit.new([request.pull_request_id]),
          MockCommand::ClearMergeability.new([request.pull_request_id]),
          MockCommand::DeleteProcessingRequests.new([request.pull_request_number]),
        ]
      end

      test "it is done if the batch is empty" do
        command = MockCommand.new
        configuration = Configuration.new(skip_rebase: false)

        result = Processor.new(command:, configuration:, requests: [], invalid_requests: []).call
        assert_empty command.actions
      end

      test "it forwards exceptions from failed transition to processing" do
        configuration = Configuration.new(skip_rebase: false)
        command = MockCommand.new(transition_to_processing: [
          ICommand::Result::Error.new(message: "something bad happened")
        ])

        request = build_request

        processor = Processor.new(command:, configuration:, requests: [request], invalid_requests: [])

        assert_raises(Errors::CommandFailed) { processor.call }
      end

      test "it forwards exceptions from failed update refs" do
        configuration = Configuration.new(skip_rebase: false)
        command = MockCommand.new(update_refs: [
          ICommand::Result::Error.new(message: "something bad happened")
        ])

        request = build_request

        processor = Processor.new(command:, configuration:, requests: [request], invalid_requests: [])

        assert_raises(Errors::CommandFailed) { processor.call }
      end

      test "failing to create a merge commit automatically retries" do
        configuration = Configuration.new(skip_rebase: false)

        command = MockCommand.new(
          create_merge_commit: [
            ICommand::Result::Error.new(message: "whimsy", permit_retry: true),
            ICommand::Result::Error.new(message: "whimsy", permit_retry: true),
            GitSystems::Commit::Failed.new(code: :unknown),
          ]
        )

        request = build_request

        result = Processor.new(
          requests: [request],
          command:,
          configuration:,
          invalid_requests: [],
        ).call

        assert_instance_of GitSystems::Commit::Failed, request.merge_commit
        assert_instance_of Request::Commits::Skipped, request.rebase_commit
        assert_equal Request::Mergeability::Indeterminate, request.current_mergeability

        assert_equal command.actions, [
          MockCommand::TransitionToProcessing.new([request.pull_request_number]),
          MockCommand::CreateMergeCommit.new([request.pull_request_id]),
          MockCommand::CreateMergeCommit.new([request.pull_request_id]),
          MockCommand::CreateMergeCommit.new([request.pull_request_id]),
          MockCommand::ClearMergeability.new([request.pull_request_id]),
          MockCommand::DeleteProcessingRequests.new([request.pull_request_number]),
        ]
      end

      test "only having invalid requests clears the queue of them" do
        configuration = Configuration.new(skip_rebase: false)
        command = MockCommand.new

        result = Processor.new(
          requests: [],
          command:,
          configuration:,
          invalid_requests: [
            Request::Invalid.new(
              reason: Request::Invalid::Reason::MissingPullRequest,
              pull_request_id: 1,
              pull_request_number: 1,
            )
          ],
        ).call

        assert_equal command.actions, [
          MockCommand::TransitionToProcessing.new([1]),
          MockCommand::DeleteProcessingRequests.new([1]),
        ]
      end

      private

      sig do
        params(
          pull_request_number: Integer,
          pull_request_id: Integer,
          base_sha: String,
          head_sha: String,
          merge_ref: String,
          rebase_ref: String,
          previous_mergeability: Request::Mergeability,
        ).returns(Request)
      end
      def build_request(
        pull_request_number: 1,
        pull_request_id: pull_request_number,
        base_sha: oid_sequence.next,
        head_sha: oid_sequence.next,
        merge_ref: "refs/pull/#{pull_request_number}/merge",
        rebase_ref: "refs/__gh__/pull/#{pull_request_number}/rebase",
        previous_mergeability: Request::Mergeability::Indeterminate
      )
        Request.new(
          pull_request_number: pull_request_number,
          pull_request_id: pull_request_id,
          pull_request_base_sha: base_sha,
          pull_request_head_sha: head_sha,
          base_ref_sha: base_sha,
          head_ref_sha: head_sha,
          rebase_ref_name: rebase_ref,
          merge_ref_name: merge_ref,
          head_ref_name: "refs/heads/feature-#{pull_request_number}",
          base_ref_name: "refs/heads/main",
          previous_mergeability:,
        )
      end

      sig { params(actual: MockCommand::Actions, expected: MockCommand::Actions).void }
      def assert_actions_performed(actual, expected)

        assert_equal \
          expected.map { _1.inspect.gsub("PullRequests::MergeCommit::ProcessorTest::MockCommand::", "") },
          actual.map { _1.inspect.gsub("PullRequests::MergeCommit::ProcessorTest::MockCommand::", "") }
      end

      sig { returns(T::Enumerator[String]) }
      def oid_sequence
        @oid_sequence ||= Enumerator.new do |y|
          value = 0
          loop do
            y << value.to_s(16).rjust(40, "0")
            value += 1
          end
        end
      end

      # Enables mocking out side effects requested by the processor. Mock results can be given to the initializer
      # as an array of results, allowing sequential calls with different outcomes.
      class MockCommand
        include ICommand
        extend T::Sig

        sig do
          params(
            transition_to_processing: T::Array[ICommand::TransitionToProcessingResult],
            create_merge_commit: T::Array[ICommand::CreateMergeCommitResult],
            create_rebase_commit: T::Array[ICommand::CreateRebaseCommitResult],
            update_refs: T::Array[ICommand::UpdateRefsResult],
            mark_pull_request_as_mergeable: T::Array[ICommand::MarkPullRequestAsMergeableResult],
            mark_pull_request_as_unmergeable: T::Array[ICommand::MarkPullRequestAsUnmergeableResult],
            clear_mergeability: T::Array[ICommand::ClearMergeabilityResult],
            delete_processing_requests: T::Array[ICommand::DeleteProcessingRequestsResult],
          ).void
        end
        def initialize(
          transition_to_processing: [],
          create_merge_commit: [],
          create_rebase_commit: [],
          update_refs: [],
          mark_pull_request_as_mergeable: [],
          mark_pull_request_as_unmergeable: [],
          clear_mergeability: [],
          delete_processing_requests: []
        )
          @actions = T.let([], Actions)
          @transition_to_processing_results = transition_to_processing
          @create_merge_commit_results = create_merge_commit
          @create_rebase_commit_results = create_rebase_commit
          @update_refs_results = update_refs
          @mark_pull_request_as_mergeable = mark_pull_request_as_mergeable
          @mark_pull_request_as_unmergeable = mark_pull_request_as_unmergeable
          @clear_mergeability = clear_mergeability
          @delete_processing_requests = delete_processing_requests
        end

        sig do
          override.params(
            pull_request_id: Integer,
            priority: Enums::Priority,
            base_repository_id: Integer,
            head_repository_id: Integer,
            merge_sha: T.nilable(String),
            merge_state: String,
            merge_conflict: T.nilable(T::Hash[T.untyped, T.untyped]),
            rebase_sha: T.nilable(String),
            rebase_state: String,
            rebase_conflict: T.nilable(T::Hash[T.untyped, T.untyped]),
          ).returns(InsertMergeCommitRequestResult)
        end
        def insert_merge_commit_request!(pull_request_id:, priority:, base_repository_id:, head_repository_id:, merge_sha:, merge_state:, merge_conflict:, rebase_sha:, rebase_state:, rebase_conflict:)
          @insert_merge_commit_request_results.shift || ICommand::Result::Success.new
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

        CreateMergeCommit = Data.define(:ids)
        sig { override.params(pull_request_id: Integer, head_sha: String, base_sha: String).returns(CreateMergeCommitResult) }
        def create_merge_commit!(pull_request_id:, head_sha:, base_sha:)
          @actions << CreateMergeCommit.new([pull_request_id])
          @create_merge_commit_results.shift || PullRequests::GitSystems::Commit::Created.new(
            sha: SecureRandom.hex(16),
            base_sha:,
            head_sha:,
          )
        end

        CreateRebaseCommit = Data.define(:ids, :merge_commit_sha, :timeout)
        sig { override.params(pull_request_id: Integer, base_sha: String, merge_commit_sha: String, timeout: Integer).returns(CreateRebaseCommitResult) }
        def create_rebase_commit!(pull_request_id:, base_sha:, merge_commit_sha:, timeout:)
          @actions << CreateRebaseCommit.new([pull_request_id], merge_commit_sha, timeout)
          @create_rebase_commit_results.shift || PullRequests::GitSystems::Commit::Created.new(
            sha: SecureRandom.hex(16),
            base_sha:,
            head_sha: merge_commit_sha,
          )
        end

        UpdateRefs = Data.define(:updates)
        sig { override.params(updates: T::Array[ICommand::RefUpdate]).returns(UpdateRefsResult) }
        def update_refs!(updates:)
          @actions << UpdateRefs.new(updates)
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

        sig do
          override.params(
            pull_request_id: Integer,
            details: T::Hash[T.untyped, T.untyped],
            type: Enums::Conflict
          ).returns(GenericResult)
        end
        def store_conflicts!(pull_request_id:, details:, type:)
          ICommand::Result::Success.new
        end

        sig { override.params(pull_request_id: Integer, type: Enums::Conflict).returns(GenericResult) }
        def clear_conflicts!(pull_request_id:, type:)
          ICommand::Result::Success.new
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

        Action = T.type_alias do
          T.any(
            TransitionToProcessing,
            CreateMergeCommit,
            CreateRebaseCommit,
            UpdateRefs,
            MarkPullRequestAsMergeable,
            MarkPullRequestAsUnmergeable,
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
end
