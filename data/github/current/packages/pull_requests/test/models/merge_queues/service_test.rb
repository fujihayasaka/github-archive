# typed: true
# frozen_string_literal: true

require "test_helper"

module MergeQueues
  class ServiceTest < GitHub::TestCase
    include HydroTestHelpers
    include HookIntegrationTestHelper

    fixtures do
      enable_feature_flag(:merge_queue)
      enable_feature_flag(:merge_queue_deploy_then_merge)

      make_trusted_oauth_apps_owner
      create(:merge_queue_integration)

      @repository = create(:repository, :has_merge_queue)
      @queue = @repository.default_merge_queue
      @queue_entry = create(:merge_queue_entry, queue: @queue, head_sha: nil)
      @actor = @queue_entry.pull_request.user

      create :hook, :web, installation_target: @repository, events: %w(pull_request)

      example_repo_snapshot
    end

    setup do
      skip unless GitHub.merge_queues_enabled?
      example_repo_restore
    end

    context "#lock_best_entry!" do
      test "it locks and returns the the MergeQueueEntry" do
        @queue_entry.update(
          state: MergeQueues::Entry::State::Mergeable::VALUE,
          head_sha: "deadbeef",
          base_sha: @repository.ref_to_sha(@queue.branch),
          created_at: 5.minutes.ago,
        )
        entry = Service::LockBestEntry.new(@repository, @queue.branch).call(actor: @actor)

        assert_equal "deadbeef", entry&.head_sha
        assert @queue_entry.reload.locked?
      end

      test "raises an error if the first entry's base_sha is not at the tip of the queue's target branch" do
        skip unless @repository.feature_enabled?(:merge_queue_validate_group_before_locking)

        @queue_entry.update(
          state: MergeQueues::Entry::State::Mergeable::VALUE,
          head_sha: "deadbeef",
          base_sha: "1" * 40,
          created_at: 5.minutes.ago,
        )

        assert_raises(Errors::NoLockableGroup) do
          Service::LockBestEntry.new(@repository, @queue.branch).call(actor: @actor)
        end
      end

      test "raises an error if there is no lockable MergeQueueEntry" do
        assert_raises(Errors::NoLockableGroup) do
          Service::LockBestEntry.new(@repository, @queue.branch).call(actor: @actor)
        end
      end

      test "raise if the requirements for the total number of MergeGroupEntries is not met" do
        @queue.update!(min_entries_to_merge: 3)
        @queue_entry.update(state: MergeQueues::Entry::State::Mergeable::VALUE, head_sha: "xxxxx")

        assert_raises(Errors::MinimumGroupSizeNotMet) do
          Service::LockBestEntry.new(@repository, @queue.branch).call(actor: @actor)
        end
      end
    end

    context "#merge_locked_entry!" do
      test "it merges the locked entry" do
        @queue.protected_branch.tap(&:enable_required_deployments).save!

        @queue_entry.update(state: MergeQueues::Entry::State::Queued::VALUE)

        merge_queue_entry_2 = create(:merge_queue_entry, queue: @queue, state: MergeQueues::Entry::State::Queued::VALUE)

        Service::Tick.new(@repository, @queue.branch).call

        merge_queue_entry_2.update(state: MergeQueues::Entry::State::Mergeable::VALUE)

        @queue.entries.reload

        Service::LockBestEntry.new(@repository, @queue.branch).call(actor: @actor)

        assert merge_queue_entry_2.reload.locked?
        assert_equal merge_queue_entry_2.entry_state, Entry::State::Mergeable

        hooks = subscribe_to_hook_delivery "*"

        result = perform_enqueued_jobs(only: [MergeQueuePostMergeJob, DeliverHookEventJob]) do
          Service::MergeLockedEntry.new(@repository, @queue.branch).call(actor: @actor)
        end
        assert result.is_a?(Service::MergeLockedEntry::Result::Success), "Expected Success result, but got #{result.class.name}"

        assert_equal 2, hooks.all_payloads.count { |payload| payload["action"] == "dequeued" && payload.key?("pull_request") }

        assert_raises ActiveRecord::RecordNotFound do
          merge_queue_entry_2.reload
        end

        assert_equal :merged, merge_queue_entry_2.pull_request.state
      end

      test "returning errors when there is no locked entry" do
        @queue.protected_branch.tap(&:enable_required_deployments).save!

        result = Service::MergeLockedEntry.new(@repository, @queue.branch).call(actor: @actor)
        assert result.is_a?(Service::MergeLockedEntry::Result::NoLockedEntryError)
      end
    end

    context "#clear!" do
      test "it clears the merge queue of all pending entries except locked entries" do
        enable_feature_flag(:skip_locked_entries_on_clear)

        # Include a locked entry.
        @queue_entry.update(locked: true)

        5.times do |i|
          create(:merge_queue_entry, queue: @queue, position: i + 2, head_sha: "xxxxxx")
        end

        assert_equal 6, @queue.entries.count

        perform_enqueued_jobs(only: MergeQueueEntryRemovedJob) do
          Service::Clear.new(@repository, @queue.branch).call(User.ghost, clear_locked_entries: false)
        end
        issue_events = IssueEvent.where(event: "removed_from_merge_queue", repository_id: @repository.id)

        assert_equal 1, @queue.entries.count
        assert_equal 5, issue_events.count

        assert_equal issue_events.pluck(:message).uniq.first, MergeQueues::Entry::RemovalReason::QueueCleared.to_s

        assert_hydro_published_partial({ event: :CLEAR }, schema: "github.merge_queue.v1.MergeQueueEvent")
      end

      test "it clears the merge queue of all pending entries even if it is locked" do
        # Include a locked entry.
        @queue_entry.update(locked: true)

        5.times do |i|
          create(:merge_queue_entry, queue: @queue, position: i + 2, head_sha: "xxxxxx")
        end

        assert_equal 6, @queue.entries.count

        perform_enqueued_jobs(only: MergeQueueEntryRemovedJob) do
          Service::Clear.new(@repository, @queue.branch).call(User.ghost)
        end
        issue_events = IssueEvent.where(event: "removed_from_merge_queue", repository_id: @repository.id)

        assert_equal 0, @queue.entries.count
        assert_equal 6, issue_events.count

        assert_equal issue_events.pluck(:message).uniq.first, MergeQueues::Entry::RemovalReason::QueueCleared.to_s

        assert_hydro_published_partial({ event: :CLEAR }, schema: "github.merge_queue.v1.MergeQueueEvent")
      end
    end
  end
end
