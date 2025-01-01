# typed: true
# frozen_string_literal: true

require "test_helper"

module MergeQueues
  class DecisionEngineTest < GitHub::TestCase
    setup do
      skip unless GitHub.merge_queues_enabled?
    end

    class TestCommand < T::Struct
      include ICommand

      BUILD_RESULT_BASE_SHA = "8" * 40
      BUILD_RESULT_HEAD_SHA = "9" * 40
      BUILD_RESULT_HEAD_REF = "main/pr-1-cdf45260ae82a84f7ed5d3bce3d2400f2a1a0f24"

      const :merge_results, T::Array[MergeResult], factory: -> { [] }
      const :finalize_rule_suite_records_results, T::Array[GenericResult], factory: -> { [] }
      const :update_merged_pull_requests_results, T::Array[GenericResult], factory: -> { [] }
      const :record_merge_stats_results, T::Array[GenericResult], factory: -> { [] }
      const :record_merge_group_failure_results, T::Array[GenericResult], factory: -> { [] }
      const :remove_results, T::Array[GenericResult], factory: -> { [] }
      const :retry_checks_results, T::Array[GenericResult], factory: -> { [] }
      const :update_results, T::Array[GenericResult], factory: -> { [] }
      const :create_ref_results, T::Array[CreateRefResult], factory: -> { [] }
      const :request_checks_results, T::Array[GenericResult], factory: -> { [] }
      const :recalculate_position_results, T::Array[GenericResult], factory: -> { [] }
      const :store_merge_conflict_results, T::Array[GenericResult], factory: -> { [] }
      const :dispatch_webhook_results, T::Array[GenericResult], factory: -> { [] }
      const :delete_ref_results, T::Array[GenericResult], factory: -> { [] }

      sig do
        override.params(
          entry: T.any(Entry, MergeQueueEntry),
          expected_base_sha: String,
          actor: T.nilable(User),
        ).returns(MergeResult)
      end
      def merge!(entry, expected_base_sha:, actor: nil)
        merge_results.shift || Result::MergeSuccess.new(
          written_at: Time.current,
          old_oid: GitHub::NULL_OID,
          new_oid: GitHub::NULL_OID,
          head_ref: entry.head_ref || "",
        )
      end

      sig do
        override.params(
          entries: T::Array[T.any(Entry, MergeQueueEntry)],
          merge_method: IConfiguration::MergeMethod,
        ).returns(GenericResult)
      end
      def finalize_rule_suite_records!(entries, merge_method:)
        finalize_rule_suite_records_results.shift || Result::Success.new
      end

      sig do
        override.params(
          entries: T::Array[T.any(Entry, MergeQueueEntry)],
          merge_result: Result::MergeSuccess,
          merge_method: IConfiguration::MergeMethod,
          merge_action: T.nilable(Symbol),
        ).returns(GenericResult)
      end
      def update_merged_pull_requests!(entries, merge_result:, merge_method:, merge_action: nil)
        update_merged_pull_requests_results.shift || Result::Success.new
      end

      sig do
        override.params(
          entries: T::Array[T.any(Entry, MergeQueueEntry)],
          merge_result: Result::MergeSuccess
        ).returns(GenericResult)
      end
      def record_merge_stats!(entries, merge_result:)
        record_merge_stats_results.shift || Result::Success.new
      end

      sig do
        override.params(
          entries: T::Array[T.any(Entry, MergeQueueEntry)],
          merge_result: Result::BranchProtectionError,
          merge_method: IConfiguration::MergeMethod,
        ).returns(GenericResult)
      end
      def record_merge_group_failure!(entries, merge_result:, merge_method:)
        record_merge_group_failure_results.shift || Result::Success.new
      end

      sig do
        override.params(
          entries: T::Array[T.any(Entry, MergeQueueEntry)],
          actor: T.nilable(User),
          reason: T.nilable(Entry::RemovalReason)
        ).returns(GenericResult)
      end
      def remove!(entries, actor: nil, reason: nil) = remove_results.shift || Result::Success.new

      sig { override.params(entry: Entry).returns(GenericResult) }
      def retry_checks!(entry) = retry_checks_results.shift || Result::Success.new

      sig { override.params(entries: T::Array[Entry]).returns(GenericResult) }
      def update!(entries) = update_results.shift || Result::Success.new

      sig { override.params(entry: Entry, base_sha: String, method: IConfiguration::MergeMethod).returns(CreateRefResult) }
      def create_ref!(entry, base_sha:, method:)
        create_ref_results.shift || Result::CreateRefSuccess.new(
          base_sha:,
          head_sha: BUILD_RESULT_HEAD_SHA,
          head_ref: BUILD_RESULT_HEAD_REF,
        )
      end

      sig { override.params(entry: Entry, create_ref_result: Result::CreateRefSuccess).returns(GenericResult) }
      def request_checks!(entry, create_ref_result:) = request_checks_results.shift || Result::Success.new

      sig { override.params(entries: EntryList).returns(GenericResult) }
      def recalculate_positions!(entries) = recalculate_position_results.shift || Result::Success.new

      sig { override.params(entry: Entry, conflict: Result::MergeConflictError).returns(GenericResult) }
      def store_merge_conflict!(entry, conflict:) = store_merge_conflict_results.shift || Result::Success.new

      sig { override.params(payload: WebHook).returns(GenericResult) }
      def dispatch_webhook!(payload) = dispatch_webhook_results.shift || Result::Success.new

      sig { override.params(feature: Symbol).returns(T::Boolean) }
      def feature_enabled?(feature) = true

      sig { override.params(entries: T::Array[T.any(Entry, MergeQueueEntry)]).returns(GenericResult) }
      def delete_refs!(entries) = delete_ref_results.shift || Result::Success.new
    end

    context "#call" do
      test "with an empty queue" do
        command = with_logging(TestCommand.new)
        configuration = build_configuration
        decision_engine = build_decision_engine(configuration:, command:, entries: [])

        assert_nothing_raised { decision_engine.call }
        assert_empty command.actions
      end

      context "with a single entry" do
        test "waiting" do
          # TODO: We currently ignore these entries
        end

        test "queued" do
          command = with_logging(TestCommand.new)
          configuration = build_configuration
          branch_sha = "2" * 40
          entry = build_entry(Entry::State::Queued.new)

          refute entry.head_ref

          decision_engine = build_decision_engine(configuration:, command:, branch_sha:, entries: [entry])

          call_time = Time.current
          Timecop.freeze(call_time) do
            decision_engine.call
          end

          assert_actions_on command, expected: [
            did_recalculate_position(entry),
            did_create_ref(entry),
            did_request_checks(entry),
            did_update(entry, to: Entry::State::AwaitingChecks.new(
              checks_requested_at: call_time,
            )),
            did_dispatch_webhook(WebHook::ChecksRequested.for(entry:)),
          ]
          assert_equal branch_sha, entry.base_sha
          assert_equal TestCommand::BUILD_RESULT_HEAD_SHA, entry.head_sha
          assert_equal 1, entry.attempts
          assert_equal TestCommand::BUILD_RESULT_HEAD_REF, entry.head_ref
        end

        test "with unmergeable head" do
          GitHub.flipper[:consider_additional_removal_reasons_for_removable].enable

          command = with_logging(TestCommand.new)
          configuration = build_configuration(grouping_strategy: IConfiguration::GroupingStrategy::HeadGreen)
          branch_sha = "b2bcada9e6a354cb4a65b889681d0ba0ba2d20ae"
          required_checks = build_required_checks

          entry_1 = build_entry(
            Entry::State::Unmergeable.new(reason: Entry::RemovalReason::AlreadyMerged),
            base_sha: branch_sha,
            head_sha: "a" * 40,
          )

          entry_2 = build_entry(
            Entry::State::AwaitingChecks.new(
              checks_requested_at: 5.minutes.ago,
            ),
            base_sha: "a" * 40,
            head_sha: TestCommand::BUILD_RESULT_HEAD_SHA,
            after: entry_1,
            requested_checks: build_requested_checks(
              required_checks,
              configuration,
              requested_at: 5.minutes.ago,
              state: Entry::RequestedCheck::State::Pending,
              attempts: 1,
              max_attempts: 0
            )
          )

          decision_engine = build_decision_engine(configuration:, command:, branch_sha:, entries: [entry_1, entry_2])
          decision_engine.call

          assert_actions_on command, expected: [
            did_remove(entry_1, because: Entry::RemovalReason::AlreadyMerged),
            did_dispatch_destroyed_webhook(entry: entry_1, because: WebHook::Destroyed::Reason::Dequeued),
            did_dispatch_dequeued_webhook(entry: entry_1, because: Entry::RemovalReason::AlreadyMerged),
          ]
        end

        test "queued, with no required checks" do
          configuration = build_configuration
          command = with_logging(TestCommand.new)
          branch_sha = "2" * 40
          entry = build_entry(Entry::State::Queued.new)

          refute entry.head_ref

          decision_engine = build_decision_engine(
            command:,
            branch_sha:,
            entries: [entry],
            configuration:,
            require_checks: false,
          )

          decision_engine.call

          assert_actions_on command, expected: [
            did_recalculate_position(entry),
            did_create_ref(entry),
            did_update(entry, to: Entry::State::Mergeable.new),
          ]
          assert_equal branch_sha, entry.base_sha
          assert_equal TestCommand::BUILD_RESULT_HEAD_SHA, entry.head_sha
          assert_equal 1, entry.attempts
          assert_equal TestCommand::BUILD_RESULT_HEAD_REF, entry.head_ref
        end

        test "awaiting checks" do
          command = with_logging(TestCommand.new)
          configuration = build_configuration
          required_checks = build_required_checks
          entry = build_entry(
            Entry::State::AwaitingChecks.new(
              checks_requested_at: 5.minutes.ago,
            ),
            requested_checks: build_requested_checks(required_checks, configuration, requested_at: 5.minutes.ago),
            base_sha: TestCommand::BUILD_RESULT_BASE_SHA,
            head_sha: TestCommand::BUILD_RESULT_HEAD_SHA,
          )
          decision_engine = build_decision_engine(configuration:, command:, entries: [entry])

          decision_engine.call

          assert_actions_on command, expected: [
            did_recalculate_position(entry)
          ]
          assert entry.awaiting_checks?
        end

        test "failing, and out of retries" do
          command = with_logging(TestCommand.new)
          configuration = build_configuration(
            max_attempts: 5,
          )
          required_checks = build_required_checks
          entry = build_entry(
            Entry::State::AwaitingChecks.new(
              checks_requested_at: 5.minutes.ago,
            ),
            base_sha: TestCommand::BUILD_RESULT_BASE_SHA,
            head_sha: TestCommand::BUILD_RESULT_HEAD_SHA,
            attempts: configuration.max_attempts,
            requested_checks: build_requested_checks(
              required_checks,
              configuration,
              state: Entry::RequestedCheck::State::Failed,
              requested_at: 5.minutes.ago,
              attempts: configuration.max_attempts,
              supports_retry: true,
            ),
          )
          decision_engine = build_decision_engine(
            command:,
            entries: [entry],
            configuration:
          )

          decision_engine.call

          assert_actions_on command, expected: [
            did_update(entry, to: Entry::State::Unmergeable.failed_checks),
            did_remove(entry, because: Entry::RemovalReason::FailedChecks),
            did_dispatch_destroyed_webhook(entry:, because: WebHook::Destroyed::Reason::Dequeued),
            did_dispatch_dequeued_webhook(entry: entry, because: Entry::RemovalReason::FailedChecks),
          ]
          assert_equal 5, entry.attempts
        end

        test "failing, with remaining retries" do
          command = with_logging(TestCommand.new)
          configuration = build_configuration(
            max_attempts: 5,
          )
          required_checks = build_required_checks
          entry = build_entry(
            Entry::State::AwaitingChecks.new(
              checks_requested_at: 5.minutes.ago,
            ),
            base_sha: TestCommand::BUILD_RESULT_BASE_SHA,
            head_sha: TestCommand::BUILD_RESULT_HEAD_SHA,
            attempts: configuration.max_attempts - 1,
            requested_checks: build_requested_checks(
              required_checks,
              configuration,
              state: Entry::RequestedCheck::State::Failed,
              requested_at: 5.minutes.ago,
              attempts: configuration.max_attempts - 1,
              supports_retry: true,
            ),
          )
          decision_engine = build_decision_engine(
            command:,
            entries: [entry],
            configuration:
          )

          call_time = Time.current

          Timecop.freeze(call_time) do
            decision_engine.call
          end

          assert_actions_on command, expected: [
            did_recalculate_position(entry),
            did_retry_checks(entry),
            did_update(entry, to: Entry::State::AwaitingChecks.new(
              checks_requested_at: T.cast(entry.state, Entry::State::AwaitingChecks).checks_requested_at,
            )),
          ]
          assert_equal 5, entry.attempts
        end

        test "mergeable" do
          command = with_logging(TestCommand.new)
          configuration = build_configuration
          required_checks = build_required_checks
          entry = build_entry(
            Entry::State::AwaitingChecks.new(
              checks_requested_at: 5.minutes.ago,
            ),
            head_sha: TestCommand::BUILD_RESULT_HEAD_SHA,
            base_sha: TestCommand::BUILD_RESULT_BASE_SHA,
            requested_checks: build_requested_checks(
              required_checks,
              configuration,
              requested_at: 5.minutes.ago,
              state: Entry::RequestedCheck::State::Success
            )
          )
          decision_engine = build_decision_engine(configuration:, command:, entries: [entry])

          decision_engine.call

          assert_actions_on command, expected: [
            did_update(entry, to: Entry::State::Mergeable.new),
            did_merge(entry),
            did_finalize_rule_suite_record(entry),
            did_update_merged_pull_request(entry),
            did_remove(entry, because: Entry::RemovalReason::Merged),
            did_record_merge_stats(entry),
            did_dispatch_destroyed_webhook(entry:, because: WebHook::Destroyed::Reason::Merged),
          ]
        end

        test "mergeable due to no required checks" do
          command = with_logging(TestCommand.new)
          configuration = build_configuration
          entry = build_entry(
            Entry::State::AwaitingChecks.new(
              checks_requested_at: 5.minutes.ago,
            ),
            head_sha: TestCommand::BUILD_RESULT_HEAD_SHA,
            base_sha: TestCommand::BUILD_RESULT_BASE_SHA,
          )
          decision_engine = build_decision_engine(
            configuration:,
            command:,
            entries: [entry],
            require_checks: false,
          )

          decision_engine.call

          assert_actions_on command, expected: [
            did_update(entry, to: Entry::State::Mergeable.new),
            did_merge(entry),
            did_finalize_rule_suite_record(entry),
            did_update_merged_pull_request(entry),
            did_remove(entry, because: Entry::RemovalReason::Merged),
            did_record_merge_stats(entry),
            did_dispatch_destroyed_webhook(entry:, because: WebHook::Destroyed::Reason::Merged),
          ]
        end

        test "mergeable, but with a changed base branch" do
          command = with_logging(TestCommand.new)
          branch_sha = "2" * 40
          configuration = build_configuration

          entry = build_entry(
            Entry::State::Mergeable.new,
            base_sha: "0" * 40,
            head_sha: "1" * 40,
          )

          decision_engine = build_decision_engine(
            command:,
            entries: [entry],
            branch_sha:,
            configuration:
          )

          call_time = Time.current
          Timecop.freeze(call_time) do
            decision_engine.call
          end

          assert_actions_on command, expected: [
            did_delete_ref(entry),
            did_update(entry, to: Entry::State::Queued.new),
            did_dispatch_destroyed_webhook(entry:, because: WebHook::Destroyed::Reason::Invalidated),
            did_recalculate_position(entry),
            did_create_ref(entry),
            did_request_checks(entry),
            did_update(entry, to: Entry::State::AwaitingChecks.new(
              checks_requested_at: call_time,
            )),
            did_dispatch_webhook(WebHook::ChecksRequested.for(entry:))
          ]
          assert_equal branch_sha, entry.base_sha
          assert_equal TestCommand::BUILD_RESULT_HEAD_SHA, entry.head_sha
          assert_equal 1, entry.attempts
        end

        test "retrying" do
          command = with_logging(TestCommand.new)
          configuration = build_configuration
          required_checks = build_required_checks
          checks_requested_at = 5.minutes.ago
          entry = build_entry(
            Entry::State::AwaitingChecks.new(
              checks_requested_at:,
            ),
            head_sha: TestCommand::BUILD_RESULT_HEAD_SHA,
            base_sha: TestCommand::BUILD_RESULT_BASE_SHA,
            requested_checks: build_requested_checks(
              required_checks,
              configuration,
              requested_at: 5.minutes.ago,
              state: Entry::RequestedCheck::State::Failed,
              attempts: 1,
              max_attempts: 2,
              supports_retry: true,
            )
          )

          decision_engine = build_decision_engine(configuration:, command:, entries: [entry])

          call_time = Time.current
          Timecop.freeze(call_time) do
            decision_engine.call
          end

          assert_actions_on command, expected: [
            did_recalculate_position(entry),
            did_retry_checks(entry),
            did_update(entry, to: Entry::State::AwaitingChecks.new(
              checks_requested_at:,
            ))
          ]
        end

        test "unmergeable due to failing tests" do
          command = with_logging(TestCommand.new)
          configuration = build_configuration
          required_checks = build_required_checks
          entry = build_entry(
            Entry::State::AwaitingChecks.new(
              checks_requested_at: 5.minutes.ago,
            ),
            head_sha: TestCommand::BUILD_RESULT_HEAD_SHA,
            base_sha: TestCommand::BUILD_RESULT_BASE_SHA,
            requested_checks: build_requested_checks(
              required_checks,
              configuration,
              requested_at: 5.minutes.ago,
              state: Entry::RequestedCheck::State::Failed,
              attempts: 1,
              max_attempts: 0
            )
          )

          decision_engine = build_decision_engine(configuration:, command:, entries: [entry])

          decision_engine.call

          assert_actions_on command, expected: [
            did_update(entry, to: Entry::State::Unmergeable.failed_checks),
            did_remove(entry, because: Entry::RemovalReason::FailedChecks),
            did_dispatch_destroyed_webhook(entry:, because: WebHook::Destroyed::Reason::Dequeued),
            did_dispatch_dequeued_webhook(entry: entry, because: Entry::RemovalReason::FailedChecks),
          ]
          assert entry.unmergeable?
        end

        test "unmergeable due to timed out tests" do
          command = with_logging(TestCommand.new)
          configuration = build_configuration(check_response_timeout: 5.minutes)
          required_checks = build_required_checks
          entry = build_entry(
            Entry::State::AwaitingChecks.new(
              checks_requested_at: 55.minutes.ago,
            ),
            head_sha: TestCommand::BUILD_RESULT_HEAD_SHA,
            base_sha: TestCommand::BUILD_RESULT_BASE_SHA,
            requested_checks: build_requested_checks(
              required_checks,
              configuration,
              requested_at: 55.minutes.ago,
              state: Entry::RequestedCheck::State::Pending,
              attempts: 1,
              max_attempts: 0
            )
          )

          decision_engine = build_decision_engine(configuration:, command:, entries: [entry])

          decision_engine.call

          assert_actions_on command, expected: [
            did_update(entry, to: Entry::State::Unmergeable.checks_timed_out),
            did_remove(entry, because: Entry::RemovalReason::ChecksTimedOut),
            did_dispatch_destroyed_webhook(entry:, because: WebHook::Destroyed::Reason::Dequeued),
            did_dispatch_dequeued_webhook(entry: entry, because: Entry::RemovalReason::ChecksTimedOut),
          ]
          assert entry.unmergeable?
        end

        test "unmergeable due to conflict" do
          command = with_logging(TestCommand.new)
          configuration = build_configuration
          entry = build_entry(
            Entry::State::Unmergeable.merge_conflict,
            base_sha: TestCommand::BUILD_RESULT_BASE_SHA,
          )

          decision_engine = build_decision_engine(configuration:, command:, entries: [entry])

          decision_engine.call

          assert_actions_on command, expected: [
            did_remove(entry, because: Entry::RemovalReason::MergeConflict),
            did_dispatch_dequeued_webhook(entry: entry, because: Entry::RemovalReason::MergeConflict),
          ]
          assert entry.unmergeable?
        end

        test "locked" do
          command = with_logging(TestCommand.new)
          configuration = build_configuration(actor_controlled_merging: true)
          entry = build_entry(
            Entry::State::Mergeable.new,
            locked: true,
            base_sha: TestCommand::BUILD_RESULT_BASE_SHA,
            head_sha: TestCommand::BUILD_RESULT_HEAD_SHA,
          )
          decision_engine = build_decision_engine(configuration:, command:, entries: [entry])

          decision_engine.call

          assert_actions_on command, expected: [
            did_recalculate_position(entry),
          ]
          assert entry.locked?
        end
      end

      context "with multiple entries" do
        test "all mergeable" do
          command = with_logging(TestCommand.new)
          configuration = build_configuration
          entry1 = build_entry(
            Entry::State::Mergeable.new,
            base_sha: TestCommand::BUILD_RESULT_BASE_SHA,
            head_sha: TestCommand::BUILD_RESULT_HEAD_SHA,
          )
          entry2 = build_entry(
            Entry::State::Mergeable.new,
            head_sha: oid_sequence.next,
            after: entry1,
          )
          decision_engine = build_decision_engine(configuration:, command:, entries: [entry1, entry2])

          decision_engine.call

          assert_actions_on command, expected: [
            did_merge(entry2),
            did_finalize_rule_suite_record(entry1),
            did_finalize_rule_suite_record(entry2),
            did_update_merged_pull_request(entry1),
            did_update_merged_pull_request(entry2),
            did_remove(entry1, because: Entry::RemovalReason::Merged),
            did_remove(entry2, because: Entry::RemovalReason::Merged),
            did_record_merge_stats(entry1),
            did_record_merge_stats(entry2),
            did_dispatch_destroyed_webhook(entry: entry1, because: WebHook::Destroyed::Reason::Merged),
            did_dispatch_destroyed_webhook(entry: entry2, because: WebHook::Destroyed::Reason::Merged),
          ]
        end

        test "all mergeable, but with a changed base branch" do
          command = with_logging(TestCommand.new)
          configuration = build_configuration
          entry1 = build_entry(
            Entry::State::Mergeable.new,
            base_sha: TestCommand::BUILD_RESULT_BASE_SHA,
            head_sha: TestCommand::BUILD_RESULT_HEAD_SHA,
          )
          entry2 = build_entry(
            Entry::State::Mergeable.new,
            base_sha: TestCommand::BUILD_RESULT_HEAD_SHA,
            head_sha: oid_sequence.next,
            after: entry1,
          )
          decision_engine = build_decision_engine(
            command:,
            entries: [entry1, entry2],
            branch_sha: oid_sequence.next,
            configuration:,
          )

          call_time = Time.current
          Timecop.freeze(call_time) do
            decision_engine.call
          end

          assert_actions_on command, expected: [
            # First we cancel
            did_delete_ref(entry1),
            did_update(entry1, to: Entry::State::Queued.new),
            did_dispatch_destroyed_webhook(entry: entry1, because: WebHook::Destroyed::Reason::Invalidated),
            did_delete_ref(entry2),
            did_update(entry2, to: Entry::State::Queued.new),
            did_dispatch_destroyed_webhook(entry: entry2, because: WebHook::Destroyed::Reason::Invalidated),

            did_recalculate_position(entry1),
            did_recalculate_position(entry2),

            # Then we rebuild
            did_create_ref(entry1),
            did_request_checks(entry1),
            did_update(entry1, to: Entry::State::AwaitingChecks.new(
              checks_requested_at: call_time,
            )),
            did_dispatch_webhook(WebHook::ChecksRequested.for(entry: entry1)),
            did_create_ref(entry2),
            did_request_checks(entry2),
            did_update(entry2, to: Entry::State::AwaitingChecks.new(
              checks_requested_at: call_time,
            )),
            did_dispatch_webhook(WebHook::ChecksRequested.for(entry: entry2)),
          ]
        end

        test "mergeable followed by unmergeable" do
          command = with_logging(TestCommand.new)
          configuration = build_configuration
          entry1 = build_entry(
            Entry::State::Mergeable.new,
            base_sha: TestCommand::BUILD_RESULT_BASE_SHA,
            head_sha: TestCommand::BUILD_RESULT_HEAD_SHA,
          )
          entry2 = build_entry(Entry::State::Unmergeable.merge_conflict, after: entry1)

          build_decision_engine(configuration:, command:, entries: [entry1, entry2]).call
          build_decision_engine(configuration:, command:, entries: [entry2]).call

          assert_actions_on command, expected: [
            did_merge(entry1),
            did_finalize_rule_suite_record(entry1),
            did_update_merged_pull_request(entry1),
            did_remove(entry1, because: Entry::RemovalReason::Merged),
            did_record_merge_stats(entry1),
            did_dispatch_destroyed_webhook(entry: entry1, because: WebHook::Destroyed::Reason::Merged),
            did_remove(entry2, because: Entry::RemovalReason::MergeConflict),
            did_dispatch_dequeued_webhook(entry: entry2, because: Entry::RemovalReason::MergeConflict),
          ]
        end

        test "mergeable followed by an unmergeable skips that entry as a base to build from" do
          command = with_logging(TestCommand.new)
          configuration = build_configuration(
            max_attempts: 10,
          )

          entry1 = build_entry(
            Entry::State::Mergeable.new,
            base_sha: TestCommand::BUILD_RESULT_BASE_SHA,
            head_sha: TestCommand::BUILD_RESULT_HEAD_SHA,
          )
          entry2 = build_entry(
            Entry::State::Unmergeable.merge_conflict,
            head_sha: nil,
            after: entry1,
          )
          entry3 = build_entry(
            Entry::State::Queued.new,
          )

          call_time = Time.current
          Timecop.freeze(call_time) do
            build_decision_engine(
              command:,
              entries: [entry1, entry2, entry3],
              configuration:,
            ).call

            build_decision_engine(
              command:,
              entries: [entry2, entry3],
              configuration:,
              branch_sha: entry1.head_sha,
            ).call

            build_decision_engine(
              command:,
              entries: [entry3],
              configuration:,
              branch_sha: entry1.head_sha,
            ).call
          end

          assert_actions_on command, expected: [
            did_merge(entry1),
            did_finalize_rule_suite_record(entry1),
            did_update_merged_pull_request(entry1),
            did_remove(entry1, because: Entry::RemovalReason::Merged),
            did_record_merge_stats(entry1),
            did_dispatch_destroyed_webhook(entry: entry1, because: WebHook::Destroyed::Reason::Merged),
            did_remove(entry2, because: Entry::RemovalReason::MergeConflict),
            did_dispatch_dequeued_webhook(entry: entry2, because: Entry::RemovalReason::MergeConflict),
            did_recalculate_position(entry3),
            did_create_ref(entry3),
            did_request_checks(entry3),
            did_update(entry3, to: Entry::State::AwaitingChecks.new(
              checks_requested_at: call_time,
            )),
            did_dispatch_webhook(WebHook::ChecksRequested.for(entry: entry3)),
          ]
        end

        test "unmergeable followed by mergeable, allowing failing entries in the group" do
          command = with_logging(TestCommand.new)
          configuration = build_configuration(
            grouping_strategy: IConfiguration::GroupingStrategy::HeadGreen,
          )
          required_checks = build_required_checks
          entry1 = build_entry(
            Entry::State::Unmergeable.failed_checks,
            base_sha: TestCommand::BUILD_RESULT_BASE_SHA,
            head_sha: TestCommand::BUILD_RESULT_HEAD_SHA,
            requested_checks: build_requested_checks(
              required_checks,
              configuration,
              state: Entry::RequestedCheck::State::Failed,
              requested_at: 5.minutes.ago,
              attempts: configuration.max_attempts
            ),
          )
          entry2 = build_entry(
            Entry::State::Mergeable.new,
            head_sha: oid_sequence.next,
            after: entry1,
          )
          decision_engine = build_decision_engine(configuration:, command:, entries: [entry1, entry2])

          decision_engine.call
          assert_actions_on command, expected: [
            did_merge(entry2),
            did_finalize_rule_suite_record(entry1),
            did_finalize_rule_suite_record(entry2),
            did_update_merged_pull_request(entry1),
            did_update_merged_pull_request(entry2),
            did_remove(entry1, because: Entry::RemovalReason::Merged),
            did_remove(entry2, because: Entry::RemovalReason::Merged),
            did_record_merge_stats(entry1),
            did_record_merge_stats(entry2),
            did_dispatch_destroyed_webhook(entry: entry1, because: WebHook::Destroyed::Reason::Merged),
            did_dispatch_destroyed_webhook(entry: entry2, because: WebHook::Destroyed::Reason::Merged),
          ]
        end

        test "unmergeable followed by mergeable, preventing failing entries in the group" do
          command = with_logging(TestCommand.new)
          configuration = build_configuration(
            grouping_strategy: IConfiguration::GroupingStrategy::AllGreen,
          )
          required_checks = build_required_checks
          entry1 = build_entry(
            Entry::State::Unmergeable.failed_checks,
            base_sha: TestCommand::BUILD_RESULT_BASE_SHA,
            head_sha: TestCommand::BUILD_RESULT_HEAD_SHA,
            requested_checks: build_requested_checks(required_checks, configuration, state: Entry::RequestedCheck::State::Failed),
          )
          entry2 = build_entry(
            Entry::State::Mergeable.new,
            head_sha: oid_sequence.next,
            after: entry1,
          )

          call_time = Time.current
          Timecop.freeze(call_time) do
            build_decision_engine(configuration:, command:, entries: [entry1, entry2], branch_sha: entry1.base_sha).call
            build_decision_engine(configuration:, command:, entries: [entry2], branch_sha: entry1.base_sha).call
          end

          assert_actions_on command, expected: [
            did_remove(entry1, because: Entry::RemovalReason::FailedChecks),
            did_dispatch_destroyed_webhook(entry: entry1, because: WebHook::Destroyed::Reason::Dequeued),
            did_dispatch_dequeued_webhook(entry: entry1, because: Entry::RemovalReason::FailedChecks),
            did_delete_ref(entry2),
            did_update(entry2, to: Entry::State::Queued.new),
            did_dispatch_destroyed_webhook(entry: entry2, because: WebHook::Destroyed::Reason::Invalidated),
            did_recalculate_position(entry2),
            did_create_ref(entry2),
            did_request_checks(entry2),
            did_update(entry2, to: Entry::State::AwaitingChecks.new(
              checks_requested_at: call_time,
            )),
            did_dispatch_webhook(WebHook::ChecksRequested.for(entry: entry2)),
          ]
        end

        test "unmergeable followed by awaiting checks" do
          command = with_logging(TestCommand.new)
          configuration = build_configuration
          required_checks = build_required_checks
          entry1 = build_entry(
            Entry::State::Unmergeable.merge_conflict,
            base_sha: TestCommand::BUILD_RESULT_BASE_SHA,
          )
          entry2 = build_entry(
            Entry::State::AwaitingChecks.new(
              checks_requested_at: 5.minutes.ago,
            ),
            requested_checks: build_requested_checks(
              required_checks,
              configuration,
              requested_at: 5.minutes.ago
            ),
            after: entry1
          )

          call_time = Time.current
          Timecop.freeze(call_time) do
            build_decision_engine(configuration:, command:, entries: [entry1, entry2]).call
            build_decision_engine(configuration:, command:, entries: [entry2]).call
          end

          assert_actions_on command, expected: [
            did_update(entry2, to: Entry::State::Queued.new),
            did_remove(entry1, because: Entry::RemovalReason::MergeConflict),
            did_dispatch_dequeued_webhook(entry: entry1, because: Entry::RemovalReason::MergeConflict),
            did_recalculate_position(entry2),
            did_create_ref(entry2),
            did_request_checks(entry2),
            did_update(entry2, to: Entry::State::AwaitingChecks.new(
              checks_requested_at: call_time,
            )),
            did_dispatch_webhook(WebHook::ChecksRequested.for(entry: entry2)),
          ]
        end

        test "several unmergeable, followed by awaiting checks" do
          command = with_logging(TestCommand.new)
          configuration = build_configuration
          required_checks = build_required_checks
          entry1 = build_entry(
            Entry::State::Unmergeable.merge_conflict,
            base_sha: TestCommand::BUILD_RESULT_BASE_SHA,
          )
          entry2 = build_entry(
            Entry::State::Unmergeable.merge_conflict,
            after: entry1,
            base_sha: TestCommand::BUILD_RESULT_BASE_SHA,
          )
          entry3 = build_entry(
            Entry::State::AwaitingChecks.new(checks_requested_at: 5.minutes.ago),
            requested_checks: build_requested_checks(
              required_checks,
              configuration,
              requested_at: 5.minutes.ago
            ),
            after: entry2,
          )

          call_time = Time.current
          Timecop.freeze(call_time) do
            build_decision_engine(
              configuration:,
              command:,
              entries: [entry1, entry2, entry3],
            ).call

            build_decision_engine(
              configuration:,
              command:,
              entries: [entry2, entry3],
            ).call

            build_decision_engine(
              configuration:,
              command:,
              entries: [entry3],
            ).call
          end

          assert_actions_on command, expected: [
            did_update(entry3, to: Entry::State::Queued.new),
            did_remove(entry1, because: Entry::RemovalReason::MergeConflict),
            did_dispatch_dequeued_webhook(entry: entry1, because: Entry::RemovalReason::MergeConflict),
            did_remove(entry2, because: Entry::RemovalReason::MergeConflict),
            did_dispatch_dequeued_webhook(entry: entry2, because: Entry::RemovalReason::MergeConflict),
            did_recalculate_position(entry3),
            did_create_ref(entry3),
            did_request_checks(entry3),
            did_update(entry3, to: Entry::State::AwaitingChecks.new(
              checks_requested_at: call_time,
            )),
            did_dispatch_webhook(WebHook::ChecksRequested.for(entry: entry3)),
          ]
        end
      end
    end

    context "build failure modes" do
      test "ref creation fails with a merge conflict" do
        command = with_logging(TestCommand.new(
          create_ref_results: [
            ICommand::Result::MergeConflictError.new,
          ],
        ))
        configuration = build_configuration
        entry = build_entry(Entry::State::Queued.new)
        decision_engine = build_decision_engine(configuration:, command:, entries: [entry])

        decision_engine.call

        assert_actions_on command, expected: [
          did_recalculate_position(entry),
          did_create_ref(entry),
          did_update(entry, to: Entry::State::Unmergeable.merge_conflict),
          did_store_merge_conflict(entry),
        ]
      end

      test "ref creation fails with a rebase conflict" do
        command = with_logging(TestCommand.new(
          create_ref_results: [
            ICommand::Result::RebaseConflictError.new,
          ],
        ))

        configuration = build_configuration
        entry = build_entry(Entry::State::Queued.new)
        decision_engine = build_decision_engine(configuration:, command:, entries: [entry])

        decision_engine.call

        assert_actions_on command, expected: [
          did_recalculate_position(entry),
          did_create_ref(entry),
          did_update(entry, to: Entry::State::Unmergeable.merge_conflict),
        ]
      end

      test "ref creation fails for an unknown reason" do
        command = with_logging(TestCommand.new(
          create_ref_results: [
            ICommand::Result::Error.new(
              message: "My test error message",
              permit_retry: false, # NOTE: This would be retryable in prod
            ),
          ],
        ))
        configuration = build_configuration
        entry = build_entry(Entry::State::Queued.new)
        decision_engine = build_decision_engine(configuration:, command:, entries: [entry])

        error = assert_raises(Errors::CommandFailed) { decision_engine.call }
        assert_equal "My test error message", error.message

        assert_actions_on command, expected: [
          did_recalculate_position(entry),
          did_create_ref(entry),
        ]
        # NOTE: The entry is not updated, so if we re-run the decision engine
        #  we will retry this same action.
      end

      test "status check request fails" do
        command = with_logging(TestCommand.new(
          request_checks_results: [
            ICommand::Result::Error.new(
              message: "Check request failed",
              permit_retry: false,
            ),
          ],
        ))
        configuration = build_configuration
        entry = build_entry(Entry::State::Queued.new)
        decision_engine = build_decision_engine(configuration:, command:, entries: [entry])

        error = assert_raises(Errors::CommandFailed) { decision_engine.call }
        assert_equal "Check request failed", error.message

        assert_actions_on command, expected: [
          did_recalculate_position(entry),
          did_create_ref(entry),
          did_request_checks(entry),
        ]
        # TODO: Verify that our ref creation is idempotent. If so, this is safe.
      end

      test "entry state update fails" do
        command = with_logging(TestCommand.new(
          update_results: [
            ICommand::Result::Error.new(
              message: "Update failed",
              permit_retry: false,
            ),
          ],
        ))
        configuration = build_configuration
        entry = build_entry(Entry::State::Queued.new)
        decision_engine = build_decision_engine(configuration:, command:, entries: [entry])

        call_time = Time.current
        error = Timecop.freeze(call_time) do
          assert_raises(Errors::CommandFailed) { decision_engine.call }
        end
        assert_equal "Update failed", error.message

        assert_actions_on command, expected: [
          did_recalculate_position(entry),
          did_create_ref(entry),
          did_request_checks(entry),
          did_update(entry, to: Entry::State::AwaitingChecks.new(
            checks_requested_at: call_time,
          )),
        ]
        # TODO: Verify that our check requests are idempotent
      end

      test "branch protections on our queue branches are handled" do
        command = with_logging(TestCommand.new(
          create_ref_results: [
            ICommand::Result::BranchProtectionError.new(message: "cannot force push to protected tag", exception: StandardError.new("oh no")),
          ],
        ))
        configuration = build_configuration
        entry = build_entry(Entry::State::Queued.new)
        decision_engine = build_decision_engine(configuration:, command:, entries: [entry])

        decision_engine.call

        assert_actions_on command, expected: [
          did_recalculate_position(entry),
          did_create_ref(entry),
          did_update(entry, to: Entry::State::Unmergeable.branch_protections),
          did_remove(entry, because: Entry::RemovalReason::BranchProtections),
          did_dispatch_dequeued_webhook(entry: entry, because: Entry::RemovalReason::BranchProtections),
        ]
      end
    end

    context "merge failure modes" do
      test "merge fails" do
        command = with_logging(TestCommand.new(
          merge_results: [
            ICommand::Result::Error.new(
              message: "Merge failed",
              permit_retry: false,
            ),
          ],
        ))
        configuration = build_configuration
        entry = build_entry(
          Entry::State::Mergeable.new,
          base_sha: TestCommand::BUILD_RESULT_BASE_SHA,
          head_sha: TestCommand::BUILD_RESULT_HEAD_SHA,
        )
        decision_engine = build_decision_engine(configuration:, command:, entries: [entry])

        error = assert_raises(Errors::CommandFailed) { decision_engine.call }
        assert_equal "Merge failed", error.message

        assert_actions_on command, expected: [
          did_merge(entry),
        ]
        # NOTE: Since this is the first action in the merge process, we can
        #  retry without any negative side effects.
      end

      # When final ref::update for a merge group fails do to branch protections, we should create a RuleSuite which
      # explains which rules failed and why.
      test "ref::update fails due to branch protections" do
        ref_update_exception = Git::Ref::RepositoryRuleViolationError.new(RuleEngine::RuleSuite.new)

        command = with_logging(TestCommand.new(
          merge_results: [
            ICommand::Result::BranchProtectionError.new(
              message: "rule violation",
              exception: ref_update_exception
            ),
          ],
        ))
        configuration = build_configuration
        required_checks = build_required_checks
        entry = build_entry(
          Entry::State::AwaitingChecks.new(
            checks_requested_at: 5.minutes.ago,
          ),
          head_sha: TestCommand::BUILD_RESULT_HEAD_SHA,
          base_sha: TestCommand::BUILD_RESULT_BASE_SHA,
          requested_checks: build_requested_checks(
            required_checks,
            configuration,
            requested_at: 5.minutes.ago,
            state: Entry::RequestedCheck::State::Success
          )
        )
        decision_engine = build_decision_engine(configuration:, command:, entries: [entry])

        decision_engine.call

        expected = [
          did_update(entry, to: Entry::State::Mergeable.new),
          did_merge(entry),
          did_record_merge_group_failure(entry),
          did_remove(entry, because: Entry::RemovalReason::BranchProtections),
          did_dispatch_destroyed_webhook(entry:, because: WebHook::Destroyed::Reason::Dequeued),
          did_dispatch_dequeued_webhook(entry:, because: Entry::RemovalReason::BranchProtections),
        ]
        expected += [did_dispatch_destroyed_webhook(entry:, because: WebHook::Destroyed::Reason::Dequeued)] unless GitHub.flipper[:mq_dont_send_duplicate_destroyed_webhooks].enabled?

        assert_actions_on(command, expected:)
      end

      test "post-merge PR updates fail" do
        command = with_logging(TestCommand.new(
          update_merged_pull_requests_results: 3.times.map do
            ICommand::Result::Error.new(
              message: "PR update failed",
              permit_retry: false,
            )
          end,
        ))

        configuration = build_configuration
        entry = build_entry(
          Entry::State::Mergeable.new,
          base_sha: TestCommand::BUILD_RESULT_BASE_SHA,
          head_sha: TestCommand::BUILD_RESULT_HEAD_SHA,
        )
        decision_engine = build_decision_engine(configuration:, command:, entries: [entry])

        decision_engine.call

        assert_actions_on command, expected: [
          did_merge(entry),
          did_finalize_rule_suite_record(entry),
          did_update_merged_pull_request(entry),
          did_remove(entry, because: Entry::RemovalReason::Merged),
          did_record_merge_stats(entry),
          did_dispatch_destroyed_webhook(entry:, because: WebHook::Destroyed::Reason::Merged),
        ]
      end

      test "attempting to merge the same PR twice does not fail" do
        command = with_logging(TestCommand.new(
          merge_results: 3.times.map do
            ICommand::Result::AlreadyMergedError.new
          end,
        ))

        configuration = build_configuration
        entry = build_entry(
          Entry::State::Mergeable.new,
          base_sha: TestCommand::BUILD_RESULT_BASE_SHA,
          head_sha: TestCommand::BUILD_RESULT_HEAD_SHA,
        )
        decision_engine = build_decision_engine(configuration:, command:, entries: [entry])

        decision_engine.call

        assert_actions_on command, expected: [
          did_merge(entry),
          did_remove(entry, because: Entry::RemovalReason::AlreadyMerged),
          did_dispatch_destroyed_webhook(entry:, because: WebHook::Destroyed::Reason::Dequeued),
        ]
      end

      test "remove merged entries fails" do
        command = with_logging(TestCommand.new(
          remove_results: [
            ICommand::Result::Error.new(
              message: "Removing entry failed",
              permit_retry: false,
            ),
          ],
        ))
        configuration = build_configuration
        entry = build_entry(
          Entry::State::Mergeable.new,
          base_sha: TestCommand::BUILD_RESULT_BASE_SHA,
          head_sha: TestCommand::BUILD_RESULT_HEAD_SHA,
        )
        decision_engine = build_decision_engine(configuration:, command:, entries: [entry])

        error = assert_raises(Errors::CommandFailed) { decision_engine.call }
        assert_equal "Removing entry failed", error.message

        assert_actions_on command, expected: [
          did_merge(entry),
          did_finalize_rule_suite_record(entry),
          did_update_merged_pull_request(entry),
          did_remove(entry, because: Entry::RemovalReason::Merged),
        ]
        # TODO: Verify that `merge!` is idempotent
      end

      test "bad head_sha on a pull request retries ref creation, then ejects the entry" do
        command = with_logging(TestCommand.new(
          create_ref_results: 3.times.map do
            ICommand::Result::GitTreeError.new
          end,
        ))
        configuration = build_configuration

        entry = build_entry(Entry::State::Queued.new)
        decision_engine = build_decision_engine(configuration:, command:, entries: [entry])

        decision_engine.call

        assert_actions_on command, expected: [
          did_recalculate_position(entry),
          did_create_ref(entry),
          did_create_ref(entry),
          did_create_ref(entry),
          did_update(entry, to: Entry::State::Unmergeable.git_tree_invalid),
          did_remove(entry, because: Entry::RemovalReason::GitTreeInvalid),
          did_dispatch_dequeued_webhook(entry: entry, because: Entry::RemovalReason::GitTreeInvalid),
        ]
      end

      test "unmergable due to git errors are skipped" do
        command = with_logging(TestCommand.new)
        configuration = build_configuration

        entry_1 = build_entry(
          Entry::State::Unmergeable.git_tree_invalid,
          base_sha: TestCommand::BUILD_RESULT_BASE_SHA,
          head_sha: nil,
        )

        entry_2 = build_entry(Entry::State::Queued.new)

        decision_engine = build_decision_engine(configuration:, command:, entries: [entry_1, entry_2])

        decision_engine.call

        assert_actions_on command, expected: [
          did_remove(entry_1, because: Entry::RemovalReason::GitTreeInvalid),
          did_dispatch_dequeued_webhook(entry: entry_1, because: Entry::RemovalReason::GitTreeInvalid),
        ]
      end

      test "conflicts are never attempted to be merged" do
        command = with_logging(TestCommand.new)
        configuration = build_configuration(grouping_strategy: IConfiguration::GroupingStrategy::HeadGreen)
        required_checks = build_required_checks

        entry1 = build_entry(
          Entry::State::AwaitingChecks.new(
            checks_requested_at: 5.minutes.ago,
          ),
          base_sha: oid_sequence.next,
          head_sha: oid_sequence.next,
          requested_checks: build_requested_checks(required_checks, configuration, requested_at: 5.minutes.ago)
        )

        entry2 = build_entry(
          Entry::State::Unmergeable.merge_conflict,
          base_sha: entry1.head_sha,
          after: entry1,
        )

        entry3 = build_entry(
          Entry::State::Mergeable.new,
          base_sha: entry1.head_sha,
          head_sha: oid_sequence.next,
          after: entry2,
        )

        build_decision_engine(configuration:, command:, entries: [entry1, entry2, entry3]).call
        build_decision_engine(configuration:, command:, entries: [entry2]).call

        assert_actions_on command, expected: [
          did_merge(entry3),
          did_finalize_rule_suite_record(entry1),
          did_finalize_rule_suite_record(entry3),
          did_update_merged_pull_request(entry1),
          did_update_merged_pull_request(entry3),
          did_remove(entry1, because: Entry::RemovalReason::Merged),
          did_remove(entry3, because: Entry::RemovalReason::Merged),
          did_record_merge_stats(entry1),
          did_record_merge_stats(entry3),
          did_dispatch_destroyed_webhook(entry: entry1, because: WebHook::Destroyed::Reason::Merged),
          did_dispatch_destroyed_webhook(entry: entry3, because: WebHook::Destroyed::Reason::Merged),
          did_remove(entry2, because: Entry::RemovalReason::MergeConflict),
          did_dispatch_dequeued_webhook(entry: entry2, because: Entry::RemovalReason::MergeConflict),
        ]
      end

      test "when merge is set to HEADGREEN and there is potentially passing CI on second entry it does not remove from queue" do
        command = with_logging(TestCommand.new)
        configuration = build_configuration(grouping_strategy: IConfiguration::GroupingStrategy::HeadGreen)
        required_checks = build_required_checks
        entry_1 = build_entry(
          Entry::State::AwaitingChecks.new(
            checks_requested_at: 5.minutes.ago,
          ),
          head_sha: TestCommand::BUILD_RESULT_HEAD_SHA,
          base_sha: TestCommand::BUILD_RESULT_BASE_SHA,
          requested_checks: build_requested_checks(
            required_checks,
            configuration,
            requested_at: 5.minutes.ago,
            state: Entry::RequestedCheck::State::Failed,
            attempts: 1,
            max_attempts: 0
          )
        )
        entry_2 = build_entry(
          Entry::State::AwaitingChecks.new(
            checks_requested_at: 5.minutes.ago,
          ),
          head_sha: TestCommand::BUILD_RESULT_HEAD_SHA,
          after: entry_1,
          requested_checks: build_requested_checks(
            required_checks,
            configuration,
            requested_at: 5.minutes.ago,
            state: Entry::RequestedCheck::State::Pending,
            attempts: 1,
            max_attempts: 0
          )
        )

        decision_engine = build_decision_engine(configuration:, command:, entries: [entry_1, entry_2])

        decision_engine.call

        assert_actions_on command, expected: [
          did_update(entry_1, to: Entry::State::Unmergeable.failed_checks),
          did_recalculate_position(entry_1),
          did_recalculate_position(entry_2),
        ]
        assert entry_1.unmergeable?
      end

      test "when the merge is set to HEADGREEN it still removes solo entries" do
        command = with_logging(TestCommand.new)
        configuration = build_configuration(
          grouping_strategy: IConfiguration::GroupingStrategy::HeadGreen,
          max_merge_entries_size: 3
        )
        required_checks = build_required_checks
        entry_1 = build_entry(
          Entry::State::AwaitingChecks.new(
            checks_requested_at: 5.minutes.ago,
          ),
          head_sha: TestCommand::BUILD_RESULT_HEAD_SHA,
          base_sha: TestCommand::BUILD_RESULT_BASE_SHA,
          solo: true,
          requested_checks: build_requested_checks(
            required_checks,
            configuration,
            requested_at: 5.minutes.ago,
            state: Entry::RequestedCheck::State::Failed,
            attempts: 1,
            max_attempts: 0,
          )
        )
        entry_2 = build_entry(
          Entry::State::AwaitingChecks.new(
            checks_requested_at: 5.minutes.ago,
          ),
          head_sha: TestCommand::BUILD_RESULT_HEAD_SHA,
          after: entry_1,
          requested_checks: build_requested_checks(
            required_checks,
            configuration,
            requested_at: 5.minutes.ago,
            state: Entry::RequestedCheck::State::Pending,
            attempts: 1,
            max_attempts: 0
          )
        )

        decision_engine = build_decision_engine(configuration:, command:, entries: [entry_1, entry_2])

        decision_engine.call

        assert_actions_on command, expected: [
          did_update(entry_1, to: Entry::State::Unmergeable.failed_checks),
          did_remove(entry_1, because: Entry::RemovalReason::FailedChecks),
          did_dispatch_destroyed_webhook(entry: entry_1, because: WebHook::Destroyed::Reason::Dequeued),
          did_dispatch_dequeued_webhook(entry: entry_1, because: Entry::RemovalReason::FailedChecks),
        ]
      end

      test "when merge is set to HEADGREEN and it respects the max group size when looking for descendent entry statuses" do
        command = with_logging(TestCommand.new)
        configuration = build_configuration(
          grouping_strategy: IConfiguration::GroupingStrategy::HeadGreen,
          max_merge_entries_size: 1
        )
        required_checks = build_required_checks
        entry_1 = build_entry(
          Entry::State::AwaitingChecks.new(
            checks_requested_at: 5.minutes.ago,
          ),
          head_sha: TestCommand::BUILD_RESULT_HEAD_SHA,
          base_sha: TestCommand::BUILD_RESULT_BASE_SHA,
          requested_checks: build_requested_checks(
            required_checks,
            configuration,
            requested_at: 5.minutes.ago,
            state: Entry::RequestedCheck::State::Failed,
            attempts: 1,
            max_attempts: 0
          )
        )
        entry_2 = build_entry(
          Entry::State::AwaitingChecks.new(
            checks_requested_at: 5.minutes.ago,
          ),
          head_sha: TestCommand::BUILD_RESULT_HEAD_SHA,
          after: entry_1,
          requested_checks: build_requested_checks(
            required_checks,
            configuration,
            requested_at: 5.minutes.ago,
            state: Entry::RequestedCheck::State::Pending,
            attempts: 1,
            max_attempts: 0
          )
        )

        decision_engine = build_decision_engine(configuration:, command:, entries: [entry_1, entry_2])

        decision_engine.call

        assert_actions_on command, expected: [
          did_update(entry_1, to: Entry::State::Unmergeable.failed_checks),
          did_remove(entry_1, because: Entry::RemovalReason::FailedChecks),
          did_dispatch_destroyed_webhook(entry: entry_1, because: WebHook::Destroyed::Reason::Dequeued),
          did_dispatch_dequeued_webhook(entry: entry_1, because: Entry::RemovalReason::FailedChecks),
        ]
      end

      test "when merge is set to ALLGREEN and first entry is in an unmergable state remove from queue" do
        command = with_logging(TestCommand.new)
        configuration = build_configuration(grouping_strategy: IConfiguration::GroupingStrategy::AllGreen)
        required_checks = build_required_checks
        entry_1 = build_entry(
          Entry::State::AwaitingChecks.new(
            checks_requested_at: 5.minutes.ago,
          ),
          head_sha: TestCommand::BUILD_RESULT_HEAD_SHA,
          base_sha: TestCommand::BUILD_RESULT_BASE_SHA,
          requested_checks: build_requested_checks(
            required_checks,
            configuration,
            requested_at: 5.minutes.ago,
            state: Entry::RequestedCheck::State::Failed,
            attempts: 1,
            max_attempts: 0
          )
        )
        entry_2 = build_entry(
          Entry::State::AwaitingChecks.new(
            checks_requested_at: 5.minutes.ago,
          ),
          head_sha: TestCommand::BUILD_RESULT_HEAD_SHA,
          after: entry_1,
          requested_checks: build_requested_checks(
            required_checks,
            configuration,
            requested_at: 5.minutes.ago,
            state: Entry::RequestedCheck::State::Pending,
            attempts: 1,
            max_attempts: 0
          )
        )

        decision_engine = build_decision_engine(configuration:, command:, entries: [entry_1, entry_2])

        decision_engine.call

        assert_actions_on command, expected: [
          did_update(entry_1, to: Entry::State::Unmergeable.failed_checks),
          did_remove(entry_1, because: Entry::RemovalReason::FailedChecks),
          did_dispatch_destroyed_webhook(entry: entry_1, because: WebHook::Destroyed::Reason::Dequeued),
          did_dispatch_dequeued_webhook(entry: entry_1, because: Entry::RemovalReason::FailedChecks),
        ]
      end
    end

    test "if we are missing a head sha its ignored" do
      command = with_logging(TestCommand.new)
      configuration = build_configuration(grouping_strategy: IConfiguration::GroupingStrategy::HeadGreen)
      required_checks = build_required_checks

      entry1 = build_entry(
        Entry::State::AwaitingChecks.new(
          checks_requested_at: 5.minutes.ago,
        ),
        requested_checks: build_requested_checks(required_checks, configuration),
        base_sha: oid_sequence.next,
        head_sha: oid_sequence.next,
      )

      entry2 = build_entry(
        Entry::State::AwaitingChecks.new(
          checks_requested_at: 5.minutes.ago,
        ),
        requested_checks: build_requested_checks(required_checks, configuration),
        base_sha: entry1.head_sha,
        head_sha: oid_sequence.next,
        after: entry1,
      )

      # Simulate a entry with an invalid head_sha.
      entry3 = build_entry(
        Entry::State::Unmergeable.merge_conflict,
        after: entry2,
        head_sha: nil,
      )

      entry4 = build_entry(
        Entry::State::Queued.new,
        after: entry3,
        requested_checks: build_requested_checks(required_checks, configuration, state: Entry::RequestedCheck::State::Success),
      )

      5.times do
        build_decision_engine(configuration:, command:, entries: [entry1, entry2, entry3, entry4]).call
      end

      # Assert we didn't introduce an infinite loop.
      assert_actions_on command, expected: [
        did_create_ref(entry4),
        did_request_checks(entry4),
        did_update(entry4, to: Entry::State::AwaitingChecks.new(
          checks_requested_at: Time.current,
        )),
        did_dispatch_webhook(WebHook::ChecksRequested.for(entry: entry4))
      ], ignoring: [
        CommandActionLogger::Action::Name::RecalculatePositions,
      ]

      # Assert we skipped the bad entry when creating a new build.
      assert_equal entry2.head_sha, entry4.base_sha
    end

    test "locked entries are treated as immutable, and its head is treated as the base_sha" do
      command = with_logging(TestCommand.new)
      configuration = build_configuration(
        grouping_strategy: IConfiguration::GroupingStrategy::HeadGreen,
        actor_controlled_merging: true,
      )
      branch_sha = oid_sequence.next

      entry_1 = build_entry(
        Entry::State::Unmergeable.failed_checks,
        base_sha: oid_sequence.next,
        head_sha: oid_sequence.next,
        locked: true
      )

      entry_2 = build_entry(
        Entry::State::Mergeable.new,
        after: entry_1,
        head_sha: oid_sequence.next,
        locked: true
      )

      entry_3 = build_entry(
        Entry::State::Queued.new,
        after: entry_2,
      )

      call_time = Time.current
      Timecop.freeze(call_time) do
        build_decision_engine(configuration:, command:, entries: [entry_1, entry_2, entry_3], branch_sha:).call
      end

      # Assert that we ignore the current branch sha when there's a locked entry.
      assert_equal entry_2.head_sha, entry_3.base_sha

      assert_actions_on command, expected: [
        did_recalculate_position(entry_1),
        did_recalculate_position(entry_2),
        did_recalculate_position(entry_3),
        did_create_ref(entry_3),
        did_request_checks(entry_3),
        did_update(entry_3, to: Entry::State::AwaitingChecks.new(
          checks_requested_at: call_time
        )),
        did_dispatch_webhook(WebHook::ChecksRequested.for(entry: entry_3)),
      ]
    end

    sig do
      params(
        state: Entry::State,
        locked: T::Boolean,
        solo: T::Boolean,
        merge_queue_entry_id: T.nilable(Integer),
        pull_request_number: T.nilable(Integer),
        pull_request_id: T.nilable(Integer),
        base_sha: T.nilable(String),
        head_sha: T.nilable(String),
        attempts: Integer,
        after: T.nilable(Entry),
        requested_checks: T.nilable(T::Array[Entry::RequestedCheck])
      ).returns(Entry)
    end
    def build_entry(state, locked: false, solo: false, merge_queue_entry_id: nil, pull_request_number: nil, pull_request_id: nil, base_sha: nil, head_sha: nil, attempts: 0, after: nil, requested_checks: nil)
      if after
        base_sha ||= after.head_sha
        merge_queue_entry_id ||= after.merge_queue_entry_id + 1
        pull_request_number ||= after.pull_request_number + 1
        pull_request_id ||= after.pull_request_id + 1
      end

      requested_checks ||= []

      Entry.new(
        state:,
        locked:,
        solo:,
        attempts:,
        requested_checks:,
        merge_queue_entry_id: merge_queue_entry_id || 1,
        pull_request_number: pull_request_number || 1,
        pull_request_id: pull_request_id || 1,
        head_ref: head_sha && "queue-ref-#{head_sha}",
        base_sha: base_sha,
        head_sha: head_sha,
        created_at: Time.now,
      )
    end

    sig do
      params(
        max_attempts: Integer,
        check_response_timeout: ActiveSupport::Duration,
        grouping_strategy: IConfiguration::GroupingStrategy,
        actor_controlled_merging: T::Boolean,
        max_merge_entries_size: Integer
      ).returns(Configuration)
    end
    def build_configuration(
      max_attempts: 5,
      check_response_timeout: 30.minutes,
      grouping_strategy: IConfiguration::GroupingStrategy::AllGreen,
      actor_controlled_merging: false,
      max_merge_entries_size: 5
    )
      Configuration.new(
        max_attempts:,
        max_concurrency: 10,
        actor_controlled_merging:,
        max_wait_for_min_merge_entries_size: 5.minutes,
        min_merge_entries_size: 1,
        max_merge_entries_size:,
        check_response_timeout:,
        grouping_strategy:,
      )
    end

    sig do
      params(
        required_check: Entry::RequiredCheck,
        configuration: Configuration,
        requested_at: T.nilable(Time),
        attempts: Integer,
        state: Entry::RequestedCheck::State,
        supports_retry: T::Boolean,
        max_attempts: Integer,
      ).returns(Entry::RequestedCheck)
    end
    def build_requested_check(required_check, configuration, requested_at: nil, attempts: 1, state: Entry::RequestedCheck::State::Pending, supports_retry: false, max_attempts: configuration.max_attempts)
      Entry::RequestedCheck.new(
        name: required_check.name,
        timeout_after: configuration.check_response_timeout,
        max_attempts:,
        attempts:,
        state:,
        supports_retry:,
        requested_at: requested_at || 5.minutes.ago,
      )
    end

    sig do
      params(
        required_checks: T::Array[Entry::RequiredCheck],
        configuration: Configuration,
        requested_at: T.nilable(Time),
        attempts: Integer,
        state: Entry::RequestedCheck::State,
        supports_retry: T::Boolean,
        max_attempts: Integer
      ).returns(T::Array[Entry::RequestedCheck])
    end
    def build_requested_checks(required_checks, configuration, requested_at: nil, attempts: 1, state: Entry::RequestedCheck::State::Pending, supports_retry: false, max_attempts: configuration.max_attempts)
      required_checks.map do |required_check|
        build_requested_check(required_check, configuration, requested_at:, attempts:, state:, supports_retry:, max_attempts:)
      end
    end

    sig { params(checks: T::Array[String]).returns(T::Array[Entry::RequiredCheck]) }
    def build_required_checks(checks: ["required-run"])
      checks.map do |name|
        Entry::RequiredCheck.new(name:)
      end
    end

    sig do
      params(
        configuration: Configuration,
        entries: T::Array[Entry],
        command: ICommand,
        branch_sha: T.nilable(String),
        require_checks: T::Boolean,
      ).returns(DecisionEngine)
    end
    def build_decision_engine(configuration:, entries:, command:, branch_sha: nil, require_checks: true)
      DecisionEngine.new(
        command:,
        branch_sha: branch_sha || entries.first&.base_sha || oid_sequence.next,
        entries: EntryList.new(entries),
        configuration:,
        require_checks:,
      )
    end

    sig { params(implementation: ICommand).returns(CommandActionLogger) }
    def with_logging(implementation)
      CommandActionLogger.new(implementation)
    end

    sig do
      params(
        command: CommandActionLogger,
        expected: T::Array[CommandActionLogger::Action],
        ignoring: T::Array[CommandActionLogger::Action::Name],
      ).void
    end
    def assert_actions_on(command, expected:, ignoring: [])
      assert_equal(
        expected.map(&:to_s),
        command.actions.lazy.reject { ignoring.include?(_1.name) }.map(&:to_s).to_a,
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

    sig { params(entry: Entry).returns(CommandActionLogger::Action) }
    def did_merge(entry)
      CommandActionLogger::Action.new(
        name: CommandActionLogger::Action::Name::Merge,
        merge_queue_entry_id: entry.merge_queue_entry_id,
        pull_request_number: entry.pull_request_number,
      )
    end

    sig { params(entry: Entry).returns(CommandActionLogger::Action) }
    def did_finalize_rule_suite_record(entry)
      CommandActionLogger::Action.new(
        name: CommandActionLogger::Action::Name::FinalizeRuleSuiteRecords,
        merge_queue_entry_id: entry.merge_queue_entry_id,
        pull_request_number: entry.pull_request_number,
      )
    end

    sig { params(entry: Entry).returns(CommandActionLogger::Action) }
    def did_update_merged_pull_request(entry)
      CommandActionLogger::Action.new(
        name: CommandActionLogger::Action::Name::UpdateMergedPullRequest,
        merge_queue_entry_id: entry.merge_queue_entry_id,
        pull_request_number: entry.pull_request_number,
      )
    end

    sig { params(entry: Entry).returns(CommandActionLogger::Action) }
    def did_record_merge_stats(entry)
      CommandActionLogger::Action.new(
        name: CommandActionLogger::Action::Name::RecordMergeStats,
        merge_queue_entry_id: entry.merge_queue_entry_id,
        pull_request_number: entry.pull_request_number,
      )
    end

    sig { params(entry: Entry).returns(CommandActionLogger::Action) }
    def did_record_merge_group_failure(entry)
      CommandActionLogger::Action.new(
        name: CommandActionLogger::Action::Name::RecordMergeGroupFailure,
        merge_queue_entry_id: entry.merge_queue_entry_id,
        pull_request_number: entry.pull_request_number,
      )
    end

    sig { params(entry: Entry, because: Entry::RemovalReason).returns(CommandActionLogger::Action) }
    def did_remove(entry, because:)
      CommandActionLogger::Action.new(
        name: CommandActionLogger::Action::Name::Remove,
        merge_queue_entry_id: entry.merge_queue_entry_id,
        pull_request_number: entry.pull_request_number,
        removal_reason: because,
      )
    end

    sig { params(entry: Entry).returns(CommandActionLogger::Action) }
    def did_retry_checks(entry)
      CommandActionLogger::Action.new(
        name: CommandActionLogger::Action::Name::RetryChecks,
        merge_queue_entry_id: entry.merge_queue_entry_id,
        pull_request_number: entry.pull_request_number,
      )
    end

    sig { params(entry: Entry, to: Entry::State).returns(CommandActionLogger::Action) }
    def did_update(entry, to:)
      CommandActionLogger::Action.new(
        name: CommandActionLogger::Action::Name::Update,
        merge_queue_entry_id: entry.merge_queue_entry_id,
        pull_request_number: entry.pull_request_number,
        state: to,
      )
    end

    sig { params(entry: Entry).returns(CommandActionLogger::Action) }
    def did_create_ref(entry)
      CommandActionLogger::Action.new(
        name: CommandActionLogger::Action::Name::CreateRef,
        merge_queue_entry_id: entry.merge_queue_entry_id,
        pull_request_number: entry.pull_request_number,
      )
    end

    sig { params(entry: Entry).returns(CommandActionLogger::Action) }
    def did_request_checks(entry)
      CommandActionLogger::Action.new(
        name: CommandActionLogger::Action::Name::RequestChecks,
        merge_queue_entry_id: entry.merge_queue_entry_id,
        pull_request_number: entry.pull_request_number,
      )
    end

    sig { params(entry: Entry).returns(CommandActionLogger::Action) }
    def did_recalculate_position(entry)
      CommandActionLogger::Action.new(
        name: CommandActionLogger::Action::Name::RecalculatePositions,
        merge_queue_entry_id: entry.merge_queue_entry_id,
        pull_request_number: entry.pull_request_number,
      )
    end

    sig { params(entry: Entry).returns(CommandActionLogger::Action) }
    def did_store_merge_conflict(entry)
      CommandActionLogger::Action.new(
        name: CommandActionLogger::Action::Name::StoreMergeConflict,
        merge_queue_entry_id: entry.merge_queue_entry_id,
        pull_request_number: entry.pull_request_number,
      )
    end

    sig { params(entry: Entry, because: WebHook::Destroyed::Reason).returns(CommandActionLogger::Action) }
    def did_dispatch_destroyed_webhook(entry:, because:)
      did_dispatch_webhook(WebHook::Destroyed.new(
        pull_request_number: entry.pull_request_number,
        pull_request_id: entry.pull_request_id,
        merge_queue_entry_id: entry.merge_queue_entry_id,
        base_sha: entry.base_sha || "0" * 40,
        head_sha: entry.head_sha || "0" * 40,
        head_ref: entry.head_ref || "placeholder-head-ref",
        reason: because,
      ))
    end

    sig { params(entry: Entry, because: Entry::RemovalReason).returns(CommandActionLogger::Action) }
    def did_dispatch_dequeued_webhook(entry:, because:)
      did_dispatch_webhook(WebHook::Dequeued.for(entry:, reason: because))
    end

    sig { params(payload: WebHook).returns(CommandActionLogger::Action) }
    def did_dispatch_webhook(payload)
      CommandActionLogger::Action.new(
        name: CommandActionLogger::Action::Name::DispatchWebhook,
        merge_queue_entry_id: payload.merge_queue_entry_id,
        pull_request_number: payload.pull_request_number,
        hook_payload: payload,
      )
    end

    sig { params(entry: Entry).returns(CommandActionLogger::Action) }
    def did_delete_ref(entry)
      CommandActionLogger::Action.for(entry:, name: CommandActionLogger::Action::Name::DeleteRef)
    end
  end
end
