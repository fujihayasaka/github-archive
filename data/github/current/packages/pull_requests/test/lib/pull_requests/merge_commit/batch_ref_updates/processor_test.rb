# typed: true
# frozen_string_literal: true

require "test_helper"
require_relative "../mock_command"

module PullRequests
  module MergeCommit
    module BatchRefUpdates
      class ProcessorTest < GitHub::TestCase
        include MockCommand::Assertions

        test "created commits perform batched ref updates" do
          command = MockCommand.new

          request = build_request(
            database_mergeable_value: nil,
            database_merge_commit_sha_value: nil,
            database_merge_conflict_record_exists: true,
            database_rebase_conflict_record_exists: true,
            merge_commit: Entity::Commits::Created.new(sha: oid_sequence.next),
            rebase_commit: Entity::Commits::Created.new(sha: oid_sequence.next),
          )

          Processor.new(command:, requests: [request], pull_request_ids: [request.pull_request_id]).call

          assert_actions_performed(command, [
            did_mark_as_processing(request),
            did_update_refs(
              merge_ref_updated(request),
              rebase_ref_updated(request),
            ),
            did_mark_pull_as_mergeable(request),
            did_clear_conflicts(request, type: Enums::Conflict::Merge),
            did_dispatch_pull_mergeability_event(request),
            did_clear_conflicts(request, type: Enums::Conflict::Rebase),
            did_delete_requests(request),
          ])
        end

        test "reusing commits does not include them in ref updates" do
          command = MockCommand.new

          merge_commit_sha = oid_sequence.next

          request = build_request(
            database_mergeable_value: true,
            database_merge_commit_sha_value: merge_commit_sha,
            database_merge_conflict_record_exists: false,
            database_rebase_conflict_record_exists: true,
            merge_commit: Entity::Commits::Reused.new(sha: merge_commit_sha),
            rebase_commit: Entity::Commits::Created.new(sha: oid_sequence.next),
          )

          Processor.new(command:, requests: [request], pull_request_ids: [request.pull_request_id]).call

          assert_actions_performed(command, [
            did_mark_as_processing(request),
            did_update_refs(
              rebase_ref_updated(request),
            ),
            did_clear_conflicts(request, type: Enums::Conflict::Rebase),
            did_delete_requests(request),
          ])
        end

        test "rebase conflicts do not affect mergeability and are not included in the ref updates" do
          command = MockCommand.new
          command.stubs(:feature_enabled?).returns(false)

          merge_commit_sha = oid_sequence.next

          request = build_request(
            database_mergeable_value: true,
            database_merge_commit_sha_value: merge_commit_sha,
            database_merge_conflict_record_exists: true,
            database_rebase_conflict_record_exists: true,
            merge_commit: Entity::Commits::Reused.new(sha: merge_commit_sha),
            rebase_commit: Entity::Commits::Conflict.new(details: {}),
          )

          Processor.new(command:, requests: [request], pull_request_ids: [request.pull_request_id]).call

          assert_actions_performed(command, [
            did_mark_as_processing(request),
            did_clear_conflicts(request, type: Enums::Conflict::Merge),
            did_store_conflicts(request, type: Enums::Conflict::Rebase, conflict: {}),
            did_delete_requests(request),
          ])
        end

        test "rebase conflicts do not affect mergeability and are not included in the ref updates if the feature flag is enabled" do
          command = MockCommand.new
          command.stubs(:feature_enabled?).returns(true)

          merge_commit_sha = oid_sequence.next

          request = build_request(
            database_mergeable_value: true,
            database_merge_commit_sha_value: merge_commit_sha,
            database_merge_conflict_record_exists: true,
            database_rebase_conflict_record_exists: true,
            merge_commit: Entity::Commits::Reused.new(sha: merge_commit_sha),
            rebase_commit: Entity::Commits::Conflict.new(details: {}),
          )

          Processor.new(command:, requests: [request], pull_request_ids: [request.pull_request_id]).call

          assert_actions_performed(command, [
            did_mark_as_processing(request),
            did_clear_conflicts(request, type: Enums::Conflict::Merge),
            did_store_conflicts(request, type: Enums::Conflict::Rebase, conflict: {}),
            did_delete_requests(request),
          ])
        end

        test "rebase deletion is not included in the ref update if an existing merge conflict exists with the feature flag" do
          command = MockCommand.new
          command.stubs(:feature_enabled?).returns(true)

          request = build_request(
            database_mergeable_value: nil,
            database_merge_commit_sha_value: nil,
            database_merge_conflict_record_exists: true,
            database_rebase_conflict_record_exists: false,
            merge_commit: Entity::Commits::Conflict.new(details: {}),
            rebase_commit: Entity::Commits::Ineligible.new,
          )

          Processor.new(command:, requests: [request], pull_request_ids: [request.pull_request_id]).call

          assert_actions_performed(command, [
            did_mark_as_processing(request),
            did_mark_pull_as_unmergeable(request),
            did_store_conflicts(request, type: Enums::Conflict::Merge, conflict: {}),
            did_delete_requests(request),
          ])
        end

        test "a conflicted request does not perform ref updates" do
          command = MockCommand.new

          request = build_request(
            database_mergeable_value: nil,
            database_merge_commit_sha_value: nil,
            database_merge_conflict_record_exists: false,
            database_rebase_conflict_record_exists: false,
            merge_commit: Entity::Commits::Conflict.new(details: {}),
            rebase_commit: Entity::Commits::Ineligible.new,
          )

          Processor.new(command:, requests: [request], pull_request_ids: [request.pull_request_id]).call

          assert_actions_performed(command, [
            did_mark_as_processing(request),
            did_update_refs(
              rebase_ref_deleted(request),
            ),
            did_mark_pull_as_unmergeable(request),
            did_store_conflicts(request, type: Enums::Conflict::Merge, conflict: {}),
            did_dispatch_pull_mergeability_event(request),
            did_delete_requests(request),
          ])
        end

        private

        sig do
          params(
            merge_commit: Request::MergeCommit,
            rebase_commit: Request::RebaseCommit,
            database_mergeable_value: T.nilable(T::Boolean),
            database_merge_commit_sha_value: T.nilable(String),
            database_merge_conflict_record_exists: T::Boolean,
            database_rebase_conflict_record_exists: T::Boolean,
            pull_request_id: Integer,
          ).returns(Request)
        end
        def build_request(
          merge_commit:,
          rebase_commit:,
          database_mergeable_value:,
          database_merge_commit_sha_value:,
          database_merge_conflict_record_exists:,
          database_rebase_conflict_record_exists:,
          pull_request_id: 1
        )
          Request.new(
            pull_request_id:,
            merge_refname: "refs/pull/#{pull_request_id}/merge",
            merge_commit:,
            rebase_refname: "refs/__gh__/pull/#{pull_request_id}/rebase",
            rebase_commit:,
            database_mergeable_value:,
            database_merge_commit_sha_value:,
            database_merge_conflict_record_exists:,
            database_rebase_conflict_record_exists:,
          )
        end

        sig { params(request: Request).returns(ICommand::RefUpdate) }
        def rebase_ref_updated(request)
          commit = request.rebase_commit

          fail "got #{commit.inspect}, expected Created" unless commit.is_a?(Entity::Commits::Created)

          ICommand::RefUpdate.new(
            pull_request_id: request.pull_request_id,
            name: request.rebase_refname,
            sha: commit.sha
          )
        end

        def rebase_ref_deleted(request)
          ICommand::RefUpdate.new(
            pull_request_id: request.pull_request_id,
            name: request.rebase_refname,
            sha: GitHub::NULL_OID
          )
        end

        sig { params(request: Request).returns(ICommand::RefUpdate) }
        def merge_ref_updated(request)
          commit = request.merge_commit

          fail "got #{commit.inspect}, expected Created" unless commit.is_a?(Entity::Commits::Created)

          ICommand::RefUpdate.new(
            pull_request_id: request.pull_request_id,
            name: request.merge_refname,
            sha: commit.sha
          )
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
      end
    end
  end
end
