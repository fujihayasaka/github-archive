# typed: true
# frozen_string_literal: true

require "test_helper"

module MergeQueues
  class CommandTest < GitHub::TestCase
    extend T::Sig
    include HookIntegrationTestHelper
    include HydroMessageJobTestHelpers
    include PushTestHelper

    fixtures do
      GitHub.flipper[:merge_queue].enable

      make_trusted_oauth_apps_owner
      create(:merge_queue_integration)

      @repository = create(:repository, :has_merge_queue)
      @queue = @repository.default_merge_queue
      @queue_entry = create(:merge_queue_entry, queue: @queue)
      @queue_entry_stat = create(:merge_queue_entry_stat, queue: @queue, entry: @queue_entry)
      @pr = @queue_entry.pull_request

      example_repo_snapshot
    end

    setup do
      skip unless GitHub.merge_queues_enabled?

      example_repo_restore
    end

    context "#remove!" do
      test "it creates the removed_from_merge_queue event using background job" do
        merge_queue_entry = T.let(@queue_entry, MergeQueueEntry)
        pull_request = T.must(@pr)

        command = Command.new(@queue, @repository, [merge_queue_entry], [])

        entry = Entry.new(
          merge_queue_entry_id: T.must(merge_queue_entry.id),
          pull_request_number: @pr.number,
          pull_request_id: @pr.id,
          state: Entry::State::AwaitingChecks.new(
            checks_requested_at: 10.minutes.ago,
          ),
          attempts: 0,
          created_at: Time.now,
          requested_checks: [],
        )

        build_result = T.cast(
          command.create_ref!(entry, base_sha: @queue.branch_head_oid, method: @queue.merge_method_type),
          ICommand::Result::CreateRefSuccess
        )

        assert_instance_of(ICommand::Result::CreateRefSuccess, build_result)

        entry.head_ref = build_result.head_ref
        merge_queue_entry.head_ref = build_result.head_ref

        refute_nil @queue.reload.queue_ref_collection.find(entry.head_ref)

        background_jobs = [
          MergeQueueDeleteRefJob,
          MergeQueuePostMergeJob,
          MergeQueueEntryRemovedJob
        ]
        # perform HydroRepositoriesOnPushJob to create a Push record
        assert_difference "IssueEvent.count", 1 do
          result = perform_enqueued_hydro_jobs(only: [HydroRepositoriesOnPushJob]) do
            perform_enqueued_jobs(only: background_jobs) do
              command.remove!([entry])
            end
          end
        end

        assert merge_queue_entry.destroyed?
        issue_event = merge_queue_entry.pull_request&.events.last
        assert_equal issue_event.event, "removed_from_merge_queue"
      end

      test "it removes the MergeQueueEntry and cleans up the related Pull Requests and head refs" do
        merge_queue_entry = T.let(@queue_entry, MergeQueueEntry)
        pull_request = T.must(@pr)

        command = Command.new(@queue, @repository, [merge_queue_entry], [])

        entry = Entry.new(
          merge_queue_entry_id: T.must(merge_queue_entry.id),
          pull_request_number: @pr.number,
          pull_request_id: @pr.id,
          state: Entry::State::AwaitingChecks.new(
            checks_requested_at: 10.minutes.ago,
          ),
          attempts: 0,
          created_at: Time.now,
          requested_checks: [],
        )

        build_result = T.cast(
          command.create_ref!(entry, base_sha: @queue.branch_head_oid, method: @queue.merge_method_type),
          ICommand::Result::CreateRefSuccess
        )

        assert_instance_of(ICommand::Result::CreateRefSuccess, build_result)

        entry.head_ref = build_result.head_ref
        merge_queue_entry.head_ref = build_result.head_ref

        refute_nil @queue.reload.queue_ref_collection.find(entry.head_ref)

        # perform HydroRepositoriesOnPushJob to create a Push record
        result = perform_enqueued_hydro_jobs(only: [HydroRepositoriesOnPushJob]) do
          perform_enqueued_jobs(only: [MergeQueueDeleteRefJob]) do
            command.remove!([entry])
          end
        end

        assert_instance_of(ICommand::Result::Success, result)

        assert merge_queue_entry.destroyed?
        refute @queue.entry_for(pull_request:)
        assert_nil pull_request.reload.merge_queue_entry

        @queue.reload.repository.clear_ref_cache

        assert_nil @queue.queue_ref_collection.find(entry.head_ref)

        unless GitHub.flipper[:merge_queue_uses_queue_refs].enabled?(@repository)
          assert_equal MergeQueues.system_actor.id, T.must(push_accessor.latest_by_after_and_ref(repository_id: @repository.id,
            ref: T.must(merge_queue_entry.qualified_head_ref),
            after: GitHub::NULL_OID)).pusher_id, "Expected the pusher to be the system actor"
        end
      end
    end

    context "#record_merge_stats!" do
      test "success" do
        entry = Entry.new({
          merge_queue_entry_id: @queue_entry.id,
          pull_request_number: @pr.number,
          pull_request_id: @pr.id,
          state: Entry::State::Queued.new,
          created_at: Time.now,
          requested_checks: [],
        })

        command = Command.new(@queue, @repository, [@queue_entry], [])
        create_ref_result = command.create_ref!(entry, base_sha: @queue.branch_head_oid, method: @queue.merge_method_type)

        fail "Expected a successful result, got: #{create_ref_result.inspect}" unless create_ref_result.is_a?(ICommand::Result::CreateRefSuccess)

        # mimic succesful check run after build requests a check
        create(:check_run, :success,
          check_suite: create(:check_suite, repository: @repository, head_sha: create_ref_result.head_sha),
          display_name: "required-run",
        )

        # mimic the call to update by updating the entry's head sha
        entry.base_sha = create_ref_result.base_sha
        entry.head_sha = create_ref_result.head_sha
        entry.head_ref = create_ref_result.head_ref

        update_result = command.update!([entry])

        fail "Expected a successful update, got #{update_result.inspect}" unless update_result.is_a?(ICommand::Result::Success)

        merge_result = command.merge!(entry, expected_base_sha: T.must(entry.base_sha))

        fail "Expected a successful merge, got: #{merge_result.inspect}" unless merge_result.is_a?(ICommand::Result::MergeSuccess)

        call_time = Time.current
        result = Timecop.freeze(call_time) do
          command.record_merge_stats!([entry], merge_result:)
        end

        assert_instance_of(ICommand::Result::Success, result)

        group_stat = T.must(MergeGroupStat.first)
        refute_nil group_stat, "Expected a MergeGroupStat to be created"
        assert_equal @queue.id, group_stat.merge_queue_id
        assert_equal @repository.id, group_stat.repository_id
        assert_equal entry.head_ref, group_stat.ref
        assert_equal @queue.branch, group_stat.base_branch
        assert_equal 1, group_stat.pull_requests_merged_count

        assert_same_time call_time, @queue_entry_stat.reload.merged_at
      end
    end

    context "#retry_checks!" do
      test "rerequests retryable checks" do
        entry = Entry.new(
          merge_queue_entry_id: @queue_entry.id,
          pull_request_number: @pr.number,
          pull_request_id: @pr.id,
          state: Entry::State::AwaitingChecks.new(
            checks_requested_at: Time.current,
          ),
          head_sha: "deadbeef",
          created_at: Time.now,
          requested_checks: [
            Entry::RequestedCheck.new(
              state: Entry::RequestedCheck::State::Failed,
              name: "required-run",
              max_attempts: 2,
              requested_at: Time.current,
              timeout_after: 60.minutes,
              supports_retry: true,
            )
          ]
        )

        check_suite = build_stubbed(
          :check_suite,
          head_sha: "deadbeef",
        )
        check_run = build_stubbed(
          :check_run, :failure,
          check_suite:,
          display_name: "required-run",
        )

        adapter = CombinedStatus::CheckRunAdapter.new(check_run)
        T.unsafe(adapter).expects(:rerequest).once

        command = Command.new(@queue, @repository, [@queue_entry], [adapter])
        result = command.retry_checks!(entry)

        fail "Expected a successful result, got: #{result.message}" if result.is_a?(ICommand::Result::Error)
      end
    end

    context "#update!" do
      test "saving changes to the database" do
        check_request_time = 10.minutes.ago
        entry = Entry.new(
          merge_queue_entry_id: @queue_entry.id,
          pull_request_number: @pr.number,
          pull_request_id: @pr.id,
          state: Entry::State::AwaitingChecks.new(
            checks_requested_at: check_request_time,
          ),
          base_sha: "deadbeef",
          head_sha: "feebdaed",
          attempts: 1,
          created_at: Time.now,
          requested_checks: [],
        )

        command = Command.new(@queue, @repository, [@queue_entry] , [])

        result = command.update!([entry])

        assert_instance_of(ICommand::Result::Success, result)

        # TODO: Update this once we change the enums in MergeQueueEntry.
        assert_equal entry.state.serialize, @queue_entry.reload.state_before_type_cast
        assert_equal "feebdaed", @queue_entry.head_sha
        assert_equal "deadbeef", @queue_entry.base_sha
        assert_equal 1, @queue_entry.attempts
        assert_same_time check_request_time, @queue_entry.checks_requested_at
      end

      test "saving unmergeable entries to the database" do
        entry = Entry.new(
          merge_queue_entry_id: @queue_entry.id,
          pull_request_number: @pr.number,
          pull_request_id: @pr.id,
          state: Entry::State::Unmergeable.new(
            reason: Entry::RemovalReason::MergeConflict,
          ),
          base_sha: nil,
          head_sha: nil,
          attempts: 0,
          created_at: Time.now,
          requested_checks: [],
        )

        command = Command.new(@queue, @repository, [@queue_entry] , [])

        result = command.update!([entry])

        assert_instance_of(ICommand::Result::Success, result)

        # TODO: Update this once we change the enums in MergeQueueEntry.
        assert_equal entry.state.serialize, @queue_entry.reload.state_before_type_cast
        assert_equal Entry::RemovalReason::MergeConflict.to_i, @queue_entry.dequeue_reason
        assert_nil @queue_entry.head_sha
        assert_nil @queue_entry.base_sha
      end

      test "saving changes to the database for multiple records" do
        models = FactoryBot.create_list(
          :merge_queue_entry, 2,
          state: Entry::State::Queued::VALUE,
          queue: @queue,
        )

        entries = [
          Entry.new(
            merge_queue_entry_id: models.first.id,
            pull_request_number: @pr.number,
            pull_request_id: @pr.id,
            state: Entry::State::AwaitingChecks.new(
              checks_requested_at: Time.current,
            ),
            created_at: Time.now,
            requested_checks: [],
          ),
          Entry.new(
            merge_queue_entry_id: models.second.id,
            pull_request_number: @pr.number,
            pull_request_id: @pr.id,
            state: Entry::State::Waiting.new,
            created_at: Time.now,
            requested_checks: [],
          ),
        ]

        command = Command.new(@queue, @repository, models, [])

        result = command.update!(entries)

        assert_instance_of(ICommand::Result::Success, result)

        # TODO: Update this once we change the enums in MergeQueueEntry.
        assert_equal entries.first.state.serialize, models.first.reload.state_before_type_cast
        assert_equal entries.second.state.serialize, models.second.reload.state_before_type_cast
      end

      test "nooping when theres no model changes" do
        # TODO: Update this once we change the enums in MergeQueueEntry.
        entry = Entry.new(
          merge_queue_entry_id: @queue_entry.id,
          pull_request_number: @pr.number,
          pull_request_id: @pr.id,
          state: Entry::State::Queued.new,
          created_at: Time.now,
          requested_checks: [],
        )

        command = Command.new(@queue, @repository, [@queue_entry], [])

        result = command.update!([entry])

        assert_instance_of(ICommand::Result::Success, result)

        # Nothing has changed, including the updated_at timestamp.
        assert_empty @queue_entry.reload.previous_changes
      end
    end

    context "#request_checks!" do
      test "it requests a check suite when the queue uses queue refs" do
        GitHub.flipper[:merge_queue_uses_queue_refs].enable(@repository)
        CheckSuite.expects(:request).once

        entry = Entry.new({
          merge_queue_entry_id: @queue_entry.id,
          pull_request_number: @pr.number,
          pull_request_id: @pr.id,
          state: Entry::State::Queued.new,
          created_at: Time.now,
          requested_checks: [],
        })

        command = Command.new(@queue, @repository, [@queue_entry], [])

        create_ref_result = T.cast(
          command.create_ref!(entry, base_sha: @queue.branch_head_oid, method: @queue.merge_method_type),
          ICommand::Result::CreateRefSuccess
        )

        @queue_entry.update(
          head_sha: create_ref_result.head_sha,
          head_ref: create_ref_result.head_ref,
          base_sha: create_ref_result.base_sha
        )

        command.request_checks!(entry, create_ref_result:)
      end

      test "does not request a check suite when using queue refs" do
        GitHub.flipper[:merge_queue_uses_queue_refs].disable(@repository)
        CheckSuite.expects(:request).never

        entry = Entry.new({
          merge_queue_entry_id: @queue_entry.id,
          pull_request_number: @pr.number,
          pull_request_id: @pr.id,
          state: Entry::State::Queued.new,
          created_at: Time.now,
          requested_checks: [],
        })

        command = Command.new(@queue, @repository, [@queue_entry], [])

        create_ref_result = T.cast(
          command.create_ref!(entry, base_sha: @queue.branch_head_oid, method: @queue.merge_method_type),
          ICommand::Result::CreateRefSuccess
        )

        @queue_entry.update(
          head_sha: create_ref_result.head_sha,
          head_ref: create_ref_result.head_ref,
          base_sha: create_ref_result.base_sha
        )

        result = command.request_checks!(entry, create_ref_result:)

        assert ICommand::Result::Success, result
      end

      test "it does not request a check suite when queue does not use use queue refs" do
        # checks are created when a push is done upon creation of the merge/squash/rebase commit
        GitHub.flipper[:merge_queue_uses_queue_refs].disable(@repository)

        entry = Entry.new({
          merge_queue_entry_id: @queue_entry.id,
          pull_request_number: @pr.number,
          pull_request_id: @pr.id,
          state: Entry::State::Queued.new,
          created_at: Time.now,
          requested_checks: [],
        })
        create_ref_result = ICommand::Result::CreateRefSuccess.new(
          head_ref: "example-ref",
          base_sha: "1" * 40,
          head_sha: "2" * 40,
        )

        command = Command.new(@queue, @repository, [@queue_entry], [])

        result = T.cast(
          command.request_checks!(entry, create_ref_result:),
          ICommand::Result::Success,
        )

        assert_instance_of ICommand::Result::Success, result
      end
    end

    context "#recalculate_positions!" do
      test "it computes from a single merge entry" do
        merge_queue_entry = T.let(@queue_entry, MergeQueueEntry)
        merge_queue_entry_2 = T.let(create(:merge_queue_entry, queue: @queue), MergeQueueEntry)
        command = Command.new(@queue, @repository, [merge_queue_entry_2, merge_queue_entry], [])

        entry = Entry.new(
          merge_queue_entry_id: T.must(merge_queue_entry.id),
          pull_request_number: @pr.number,
          pull_request_id: @pr.id,
          state: Entry::State::AwaitingChecks.new(
            checks_requested_at: 5.minutes.ago,
          ),
          attempts: 0,
          created_at: Time.now,
          requested_checks: [],
        )

        entry_2 = Entry.new(
          merge_queue_entry_id: T.must(merge_queue_entry_2.id),
          pull_request_number: @pr.number,
          pull_request_id: @pr.id,
          state: Entry::State::AwaitingChecks.new(
            checks_requested_at: 5.minutes.ago,
          ),
          attempts: 0,
          created_at: Time.now,
          requested_checks: [],
        )

        result = T.cast(
          command.recalculate_positions!(EntryList.new([entry_2, entry])),
          ICommand::Result::Success
        )

        assert_instance_of(ICommand::Result::Success, result)

        assert_equal 1, merge_queue_entry_2.reload.position
        assert_equal 2, merge_queue_entry.reload.position
      end

      test "it returns an error when an ActiveRecord failure occurs" do
        command = Command.new(@queue, @repository, [], [])

        entry = Entry.new(
          merge_queue_entry_id: 99,
          pull_request_number: @pr.number,
          pull_request_id: @pr.id,
          state: Entry::State::AwaitingChecks.new(
            checks_requested_at: 5.minutes.ago,
          ),
          attempts: 0,
          created_at: Time.now,
          requested_checks: [],
        )

        result = T.cast(
          command.recalculate_positions!(EntryList.new([entry])),
          ICommand::Result::Error
        )

        assert_instance_of(ICommand::Result::Error, result)

        refute result.permit_retry
      end
    end

    context "#record_merge_conflict!" do
      test "it writes to pull_request_conflicts" do
        @queue_entry.update(base_sha: "1" * 40, head_sha: "2" * 40)

        command = Command.new(@queue, @repository, [@queue_entry], [])
        entry = Entry.new(
          merge_queue_entry_id: @queue_entry.id,
          pull_request_number: @pr.number,
          pull_request_id: @pr.id,
          state: Entry::State::Unmergeable.merge_conflict,
          created_at: Time.current,
          requested_checks: [],
        )
        conflict = ICommand::Result::MergeConflictError.new(
          details: {
            base: @queue_entry.base_sha,
            head: @queue_entry.head_sha,
            conflicted_files: { "example" => true }
          }
        )

        result = command.store_merge_conflict!(entry, conflict:)

        assert_instance_of(ICommand::Result::Success, result)
        assert_equal(
          ["example"],
          @queue_entry.conflicting_files
        )
      end
    end

    context "#dispatch_webhook" do
      context "checks_requested" do
        test "delivers a merge_group.checks_requested webhook payload" do
          hook = create(:hook, :web, installation_target: @repository, events: %w(merge_group))
          deliveries = subscribe_to_hook_delivery("merge_group")

          entry = Entry.new({
            merge_queue_entry_id: @queue_entry.id,
            pull_request_number: @pr.number,
            pull_request_id: @pr.id,
            state: Entry::State::Queued.new,
            created_at: Time.now,
            requested_checks: [],
          })

          command = Command.new(@queue, @repository, [@queue_entry], [])

          create_ref_result = T.cast(
            command.create_ref!(entry, base_sha: @queue.branch_head_oid, method: @queue.merge_method_type),
            ICommand::Result::CreateRefSuccess
          )

          @queue_entry.update(
            head_sha: create_ref_result.head_sha,
            head_ref: create_ref_result.head_ref,
            base_sha: create_ref_result.base_sha
          )

          result = perform_enqueued_jobs(only: [DeliverHookEventJob]) do
            command.dispatch_webhook!(WebHook::ChecksRequested.for(entry:))
          end

          assert_instance_of ICommand::Result::Success, result

          delivery = deliveries.payload_for_hook(hook)

          assert delivery
          assert_equal "checks_requested", delivery[:action]
          assert_equal @queue_entry.base_sha, delivery.dig(:merge_group, :base_sha)
          assert_equal @queue_entry.qualified_head_ref, delivery.dig(:merge_group, :head_ref)
          assert_equal @queue_entry.head_sha, delivery.dig(:merge_group, :head_sha)
          assert_equal @queue_entry.head_sha, delivery.dig(:merge_group, :head_commit, :id)
        end

        test "rejects duplicates" do
          entry = Entry.new({
            merge_queue_entry_id: @queue_entry.id,
            pull_request_number: @pr.number,
            pull_request_id: @pr.id,
            state: Entry::State::Queued.new,
            created_at: Time.now,
            requested_checks: [],
          })
          command = Command.new(@queue, @repository, [@queue_entry], [])

          first_result = command.dispatch_webhook!(WebHook::ChecksRequested.for(entry:))
          second_result = command.dispatch_webhook!(WebHook::ChecksRequested.for(entry:))

          assert_instance_of ICommand::Result::Success, first_result
          assert_instance_of ICommand::Result::Error, second_result
          assert_equal "duplicate_webhook_dispatch", second_result.try(:message)
          assert_equal false, second_result.try(:permit_retry)
        end
      end

      context "destroyed" do
        test "delivers a merge_group.destroyed webhook payload" do
          hook = create(:hook, :web, installation_target: @repository, events: %w(merge_group))
          deliveries = subscribe_to_hook_delivery("merge_group")

          entry = Entry.new({
            merge_queue_entry_id: @queue_entry.id,
            pull_request_number: @pr.number,
            pull_request_id: @pr.id,
            head_ref: "example-head-ref",
            head_sha: "e91a032dc9f19058a375fb3db68c9dda73527d13",
            base_sha: "cdf45260ae82a84f7ed5d3bce3d2400f2a1a0f24",
            state: Entry::State::Queued.new,
            created_at: Time.now,
            requested_checks: [],
          })

          command = Command.new(@queue, @repository, [@queue_entry], [])
          @queue_entry.destroy!

          result = perform_enqueued_jobs(only: [DeliverHookEventJob]) do
            command.dispatch_webhook!(
              WebHook::Destroyed.for(entry:, reason: WebHook::Destroyed::Reason::Dequeued)
            )
          end

          assert_instance_of ICommand::Result::Success, result

          delivery = deliveries.payload_for_hook(hook)

          assert delivery
          assert_equal "destroyed", delivery[:action]
          assert_equal "dequeued", delivery[:reason]
          assert_equal entry.base_sha, delivery.dig(:merge_group, :base_sha)
          assert_equal "#{@queue.ref_prefix}#{entry.head_ref}", delivery.dig(:merge_group, :head_ref)
          assert_equal entry.head_sha, delivery.dig(:merge_group, :head_sha)
          assert_equal entry.head_sha, delivery.dig(:merge_group, :head_commit, :id)
        end
      end
    end
  end
end
