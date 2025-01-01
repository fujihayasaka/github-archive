# typed: true
# frozen_string_literal: true

require "test_helper"
require_relative "../mock_command"

module PullRequests
  module MergeCommit
    module CreateCommits
      class ProcessorTest < GitHub::TestCase
        include MockCommand::Assertions

        test "pending commits generate a new set of commits and request a ref update" do
          base_branch_sha = oid_sequence.next
          head_branch_sha = oid_sequence.next
          merge_commit_sha = oid_sequence.next
          rebase_commit_sha = oid_sequence.next

          command = MockCommand.new(
            create_merge_commit: [
              GitSystems::Commit::Created.new(
                sha: merge_commit_sha,
                base_sha: base_branch_sha,
                head_sha: head_branch_sha,
              )
            ],

            create_rebase_commit: [
              GitSystems::Commit::Created.new(
                sha: rebase_commit_sha,
                base_sha: base_branch_sha,
                head_sha: merge_commit_sha,
              )
            ]
          )

          request = build_request(
            base_branch_sha:,
            head_branch_sha:,
            merge_commit: Entity::Commits::Pending.new,
            database_merge_conflict_record_exists: false,
            rebase_commit: Entity::Commits::Pending.new,
            database_mergeable_value: nil,
            database_merge_commit_sha_value: nil,
          )

          result = Processor.new(command:, request:).call

          assert_instance_of(Entity::Commits::Created, result.merge_commit)
          assert_instance_of(Entity::Commits::Created, result.rebase_commit)

          assert_actions_performed(command, [
            did_create_merge_commit(request, base_sha: base_branch_sha, head_sha: head_branch_sha),
            did_create_rebase_commit(request, base_sha: base_branch_sha, merge_commit_sha:),
            did_insert_merge_commit_request(request,
              merge_sha: merge_commit_sha,
              merge_state: "created",
              merge_conflict: nil,
              rebase_sha: rebase_commit_sha,
              rebase_state: "created",
              rebase_conflict: nil
            ),
          ])
        end

        test "conflicting merge commits result in an inserted request" do
          base_branch_sha = oid_sequence.next
          head_branch_sha = oid_sequence.next
          merge_conflict = {
            conflicted_files: {},
            more_conflicted_files: false
          }

          command = MockCommand.new(
            create_merge_commit: [
              GitSystems::Commit::Conflict.new(details: merge_conflict)
            ]
          )

          request = build_request(
            base_branch_sha:,
            head_branch_sha:,
            merge_commit: Entity::Commits::Pending.new,
            database_merge_conflict_record_exists: false,
            rebase_commit: Entity::Commits::Pending.new,
            database_mergeable_value: nil,
            database_merge_commit_sha_value: nil,
          )

          result = Processor.new(command:, request:).call

          assert_instance_of(Entity::Commits::Conflict, result.merge_commit)
          assert_instance_of(Entity::Commits::Invalid, result.rebase_commit)

          assert_actions_performed(command, [
            did_create_merge_commit(request, base_sha: base_branch_sha, head_sha: head_branch_sha),
            did_insert_merge_commit_request(request,
              merge_sha: nil,
              merge_state: "conflict",
              merge_conflict:,
              rebase_sha: nil,
              rebase_state: "invalid|merge_commit_conflict",
              rebase_conflict: nil
            ),
          ])
        end

        test "invalid merge commits do not trigger a merge commit request" do
          base_branch_sha = oid_sequence.next
          head_branch_sha = oid_sequence.next

          command = MockCommand.new(
            create_merge_commit: [GitSystems::Commit::Failed.new(code: :already_merged)]
          )

          request = build_request(
            base_branch_sha:,
            head_branch_sha:,
            merge_commit: Entity::Commits::Pending.new,
            database_merge_conflict_record_exists: false,
            rebase_commit: Entity::Commits::Pending.new,
            database_mergeable_value: nil,
            database_merge_commit_sha_value: nil,
          )

          result = Processor.new(command:, request:).call

          assert_instance_of(Entity::Commits::Invalid, result.merge_commit)
          assert_instance_of(Entity::Commits::Invalid, result.rebase_commit)

          assert_actions_performed(command, [
            did_create_merge_commit(request, base_sha: base_branch_sha, head_sha: head_branch_sha),
          ])
        end

        context "timeouts" do
          test "merge commits are retryable resulting in an invalid commit and not adding a request record" do
            base_branch_sha = oid_sequence.next
            head_branch_sha = oid_sequence.next

            command = MockCommand.new(
              create_merge_commit: 3.times.map do
                ICommand::Result::Timeout.new(exception: Timeout::Error.new)
              end
            )

            request = build_request(
              base_branch_sha:,
              head_branch_sha:,
              merge_commit: Entity::Commits::Pending.new,
              database_merge_conflict_record_exists: false,
              rebase_commit: Entity::Commits::Pending.new,
              database_mergeable_value: nil,
              database_merge_commit_sha_value: nil,
            )

            result = Processor.new(command:, request:).call

            assert_instance_of(Entity::Commits::Invalid, result.merge_commit)
            assert_instance_of(Entity::Commits::Invalid, result.rebase_commit)

            assert_actions_performed(command, [
              did_create_merge_commit(request, base_sha: base_branch_sha, head_sha: head_branch_sha, attempts: 3),
            ])
          end

          test "rebase commits are retryable resulting in an invalid commit" do
            base_branch_sha = oid_sequence.next
            head_branch_sha = oid_sequence.next
            merge_sha = oid_sequence.next

            command = MockCommand.new(
              create_merge_commit: [
                GitSystems::Commit::Created.new(
                  sha: merge_sha,
                  base_sha: base_branch_sha,
                  head_sha: head_branch_sha
                ),
              ],
              create_rebase_commit: 3.times.map do
                ICommand::Result::Timeout.new(exception: Timeout::Error.new)
              end
            )

            request = build_request(
              base_branch_sha:,
              head_branch_sha:,
              merge_commit: Entity::Commits::Pending.new,
              database_merge_conflict_record_exists: false,
              rebase_commit: Entity::Commits::Pending.new,
              database_mergeable_value: nil,
              database_merge_commit_sha_value: nil,
            )

            result = Processor.new(command:, request:).call

            assert_instance_of(Entity::Commits::Created, result.merge_commit)
            assert_instance_of(Entity::Commits::Invalid, result.rebase_commit)

            assert_actions_performed(command, [
              did_create_merge_commit(request, base_sha: base_branch_sha, head_sha: head_branch_sha),
              did_create_rebase_commit(request, base_sha: base_branch_sha, merge_commit_sha: merge_sha, attempts: 3),
              did_insert_merge_commit_request(request,
                merge_sha:,
                merge_state: "created",
                merge_conflict: nil,
                rebase_sha: nil,
                rebase_state: "invalid|timeout",
                rebase_conflict: nil
              ),
            ])
          end
        end

        context "up to date commits" do
          test "performs no actions when everything is up to date" do
            base_branch_sha = oid_sequence.next
            head_branch_sha = oid_sequence.next
            merge_commit_sha = oid_sequence.next
            rebase_commit_sha = oid_sequence.next

            command = MockCommand.new

            request = build_request(
              base_branch_sha:,
              head_branch_sha:,
              database_merge_conflict_record_exists: false,
              database_mergeable_value: true,
              database_merge_commit_sha_value: merge_commit_sha,
              merge_commit: Entity::Commits::Found.new(
                sha: merge_commit_sha,
                base_sha: base_branch_sha,
                head_sha: head_branch_sha,
              ),
              rebase_commit: Entity::Commits::Found.new(
                sha: rebase_commit_sha,
                base_sha: base_branch_sha,
                head_sha: merge_commit_sha,
              ),
            )

            result = Processor.new(command:, request:).call

            assert_instance_of(Entity::Commits::Reused, result.merge_commit)
            assert_instance_of(Entity::Commits::Reused, result.rebase_commit)

            assert_actions_performed(command, [])
          end

          test "inserts a request when the mergeable column is incorrect" do
            base_branch_sha = oid_sequence.next
            head_branch_sha = oid_sequence.next
            merge_commit_sha = oid_sequence.next
            rebase_commit_sha = oid_sequence.next

            command = MockCommand.new

            request = build_request(
              base_branch_sha:,
              head_branch_sha:,
              merge_commit: Entity::Commits::Found.new(
                sha: merge_commit_sha,
                base_sha: base_branch_sha,
                head_sha: head_branch_sha,
              ),
              database_merge_conflict_record_exists: false,
              rebase_commit: Entity::Commits::Found.new(
                sha: rebase_commit_sha,
                base_sha: base_branch_sha,
                head_sha: merge_commit_sha,
              ),
              database_mergeable_value: nil,
              database_merge_commit_sha_value: merge_commit_sha,
            )

            result = Processor.new(command:, request:).call

            assert_instance_of(Entity::Commits::Reused, result.merge_commit)
            assert_instance_of(Entity::Commits::Reused, result.rebase_commit)

            assert_actions_performed(command, [
              did_insert_merge_commit_request(request,
                merge_sha: merge_commit_sha,
                merge_state: "reused",
                merge_conflict: nil,
                rebase_sha: rebase_commit_sha,
                rebase_state: "reused",
                rebase_conflict: nil
              ),
            ])
          end

          test "inserts a request when the merge_commit_sha column is incorrect" do
            base_branch_sha = oid_sequence.next
            head_branch_sha = oid_sequence.next
            merge_commit_sha = oid_sequence.next
            rebase_commit_sha = oid_sequence.next

            command = MockCommand.new

            request = build_request(
              base_branch_sha:,
              head_branch_sha:,
              merge_commit: Entity::Commits::Found.new(
                sha: merge_commit_sha,
                base_sha: base_branch_sha,
                head_sha: head_branch_sha,
              ),
              database_merge_conflict_record_exists: false,
              rebase_commit: Entity::Commits::Found.new(
                sha: rebase_commit_sha,
                base_sha: base_branch_sha,
                head_sha: merge_commit_sha,
              ),
              database_mergeable_value: true,
              database_merge_commit_sha_value: nil,
            )

            result = Processor.new(command:, request:).call

            assert_instance_of(Entity::Commits::Reused, result.merge_commit)
            assert_instance_of(Entity::Commits::Reused, result.rebase_commit)

            assert_actions_performed(command, [
              did_insert_merge_commit_request(request,
                merge_sha: merge_commit_sha,
                merge_state: "reused",
                merge_conflict: nil,
                rebase_sha: rebase_commit_sha,
                rebase_state: "reused",
                rebase_conflict: nil
              ),
            ])
          end
        end

        context "with found merge commits" do
          test "it generates new commits when the found commit does not correct parents" do
            base_branch_sha = oid_sequence.next
            head_branch_sha = oid_sequence.next
            merge_commit_sha = oid_sequence.next
            rebase_commit_sha = oid_sequence.next

            command = MockCommand.new(
              create_merge_commit: [
                GitSystems::Commit::Created.new(
                  sha: merge_commit_sha,
                  base_sha: base_branch_sha,
                  head_sha: head_branch_sha,
                )
              ],
              create_rebase_commit: [
                GitSystems::Commit::Created.new(
                  sha: rebase_commit_sha,
                  base_sha: base_branch_sha,
                  head_sha: merge_commit_sha,
                )
              ]
            )

            request = build_request(
              base_branch_sha:,
              head_branch_sha:,
              merge_commit: Entity::Commits::Found.new(
                sha: merge_commit_sha,
                base_sha: oid_sequence.next, # simulate a changed base branch,
                head_sha: head_branch_sha,
              ),
              database_merge_conflict_record_exists: false,
              rebase_commit: Entity::Commits::Found.new(
                sha: rebase_commit_sha,
                base_sha: oid_sequence.next, # simulate a changed base branch
                head_sha: head_branch_sha,
              ),
              database_mergeable_value: nil,
              database_merge_commit_sha_value: merge_commit_sha,
            )

            Processor.new(command:, request:).call

            assert_actions_performed(command, [
              did_create_merge_commit(request, base_sha: base_branch_sha, head_sha: head_branch_sha),
              did_create_rebase_commit(request, base_sha: base_branch_sha, merge_commit_sha:),
              did_insert_merge_commit_request(request,
                merge_state: "created",
                merge_sha: merge_commit_sha,
                merge_conflict: nil,
                rebase_state: "created",
                rebase_sha: rebase_commit_sha,
                rebase_conflict: nil
              ),
            ])
          end
        end

        context "up to date merge commit" do
          test "with invalid rebase commit generates a new rebase commit for ref updates" do
            base_branch_sha = oid_sequence.next
            head_branch_sha = oid_sequence.next
            merge_commit_sha = oid_sequence.next
            rebase_commit_sha = oid_sequence.next

            command = MockCommand.new(
              create_rebase_commit: [
                GitSystems::Commit::Created.new(
                  sha: rebase_commit_sha,
                  base_sha: base_branch_sha,
                  head_sha: merge_commit_sha,
                )
              ]
            )

            request = build_request(
              base_branch_sha:,
              head_branch_sha:,
              merge_commit: Entity::Commits::Found.new(
                sha: merge_commit_sha,
                base_sha: base_branch_sha,
                head_sha: head_branch_sha,
              ),
              database_merge_conflict_record_exists: false,
              rebase_commit: Entity::Commits::Found.new(
                sha: rebase_commit_sha,
                base_sha: base_branch_sha,
                head_sha: oid_sequence.next, # simulate a previous merge commit
              ),
              database_mergeable_value: nil,
              database_merge_commit_sha_value: merge_commit_sha,
            )

            Processor.new(command:, request:).call

            assert_actions_performed(command, [
              did_create_rebase_commit(request, base_sha: base_branch_sha, merge_commit_sha:),
              did_insert_merge_commit_request(request,
                merge_state: "reused",
                merge_sha: merge_commit_sha,
                merge_conflict: nil,
                rebase_state: "created",
                rebase_sha: rebase_commit_sha,
                rebase_conflict: nil
              ),
            ])
          end

          test "with a skipped rebase commit is ignored" do
            base_branch_sha = oid_sequence.next
            head_branch_sha = oid_sequence.next
            merge_commit_sha = oid_sequence.next

            command = MockCommand.new

            request = build_request(
              base_branch_sha:,
              head_branch_sha:,
              database_mergeable_value: true,
              database_merge_commit_sha_value: merge_commit_sha,
              database_merge_conflict_record_exists: false,
              merge_commit: Entity::Commits::Found.new(
                sha: merge_commit_sha,
                base_sha: base_branch_sha,
                head_sha: head_branch_sha,
              ),
              rebase_commit: Entity::Commits::Skipped.new,
            )

            result = Processor.new(command:, request:).call

            assert_actions_performed(command, [])

            assert_instance_of(Entity::Commits::Reused, result.merge_commit)
            assert_instance_of(Entity::Commits::Skipped, result.rebase_commit)
          end
        end

        private

        sig do
          params(
            base_branch_sha: String,
            head_branch_sha: String,
            merge_commit: Request::MergeCommit,
            rebase_commit: Request::RebaseCommit,
            database_merge_conflict_record_exists: T::Boolean,
            database_mergeable_value: T.nilable(T::Boolean),
            database_merge_commit_sha_value: T.nilable(String),
            pull_request_id: Integer,
          ).returns(Request)
        end
        def build_request(
          base_branch_sha:,
          head_branch_sha:,
          merge_commit:,
          rebase_commit:,
          database_merge_conflict_record_exists:,
          database_mergeable_value:,
          database_merge_commit_sha_value:,
          pull_request_id: 1
        )
          Request.new(
            pull_request_id:,
            priority: Enums::Priority::High,
            base_repository_id: 1,
            head_repository_id: 1,
            base_branch_sha:,
            head_branch_sha:,
            rebase_commit:,
            merge_commit:,
            database_merge_conflict_record_exists:,
            database_mergeable_value:,
            database_merge_commit_sha_value:,
          )
        end

        sig do
          params(
            request: Request,
            merge_sha: T.nilable(String),
            merge_state: String,
            merge_conflict: T.untyped,
            rebase_sha: T.nilable(String),
            rebase_state: String,
            rebase_conflict: T.untyped,
          ).returns(MockCommand::InsertMergeCommitRequest)
        end
        def did_insert_merge_commit_request(request, merge_sha:, merge_state:, merge_conflict:, rebase_sha:, rebase_state:, rebase_conflict:)
          MockCommand::InsertMergeCommitRequest.new(
            request.pull_request_id,
            request.priority,
            request.base_repository_id,
            request.head_repository_id,
            merge_sha,
            merge_state,
            merge_conflict,
            rebase_sha,
            rebase_state,
            rebase_conflict,
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
