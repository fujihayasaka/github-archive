# typed: true
# frozen_string_literal: true

require "test_helper"

module MergeQueues
  module Service
    class RemoveEntryTest < GitHub::TestCase
      fixtures do
        make_trusted_oauth_apps_owner
        create(:merge_queue_integration)

        @repository = create(:repository, :has_merge_queue)
        @queue = @repository.default_merge_queue
        @queue_entry = create(:merge_queue_entry, queue: @queue, head_sha: nil)
        @actor = @queue_entry.pull_request.user

        create :hook, :web, installation_target: @repository, events: %w(merge_group pull_request)

        example_repo_snapshot
      end

      setup do
        skip unless GitHub.merge_queues_enabled?

        enable_feature_flag(:merge_queue, @repository)

        # Disabling science experiments because the additional instrumentation
        # will cause all tests that are checking expected 'GitHub.instrument' calls to fail.
        GitHub::Experiment.any_instance.stubs(:enabled?).returns(false)
        example_repo_restore
      end

      test "it removes an entry when a user dequeues it" do
        service = RemoveEntry.new(@repository, @queue.branch)

        service.call(entry: @queue_entry, actor: @actor)

        assert_raises ActiveRecord::RecordNotFound do
          @queue_entry.reload
        end
      end

      test "it raises an error when trying to remove a locked entry" do
        service = RemoveEntry.new(@repository, @queue.branch)
        @queue_entry.update!(locked: true)

        assert_raises Errors::GroupLocked do
          service.call(entry: @queue_entry, actor: @actor)
        end
      end

      test "it creates an issue_event with manual the removal reason" do
        service = RemoveEntry.new(@repository, @queue.branch)
        service.call(entry: @queue_entry, actor: @actor)
        issue_event = IssueEvent.find_by(issue_id: @queue_entry.pull_request.id, event: "removed_from_merge_queue")

        if issue_event.try(:message)
          assert_equal issue_event.try(:message), Entry::RemovalReason::Manual.to_s
        end
      end

      test "it dispatches a web hook event if the entry has a merge commit" do
        @queue_entry.update!(
          head_ref: "example-head-ref",
          head_sha: "1" * 40,
          base_sha: "2" * 40,
        )

        GitHub.expects(:instrument).with(
          "merge_group.destroyed",
          action: :destroyed,
          reason: :dequeued,
          actor_id: MergeQueues.system_actor.id,
          pull_request_id: @queue_entry.pull_request_id,
          qualified_head_ref: "#{@queue.ref_prefix}example-head-ref",
          head_sha: "1" * 40,
          base_sha: "2" * 40,
        ).once

        GitHub.expects(:instrument).with(
          "pull_request.dequeued",
          pull_request_id: @queue_entry.pull_request.id,
          actor_id: @actor.id,
          reason: :MANUAL,
        ).once

        service = RemoveEntry.new(@repository, @queue.branch)
        service.call(entry: @queue_entry, actor: @actor)
      end

      test "it does not dispatch a web hook event if the entry does not have a merge commit" do
        @queue_entry.update!(
          head_ref: nil,
          head_sha: nil,
          base_sha: nil,
        )

        GitHub.expects(:instrument).with(
          "pull_request.dequeued",
          pull_request_id: @queue_entry.pull_request.id,
          actor_id: @actor.id,
          reason: :MANUAL,
        ).once

        service = RemoveEntry.new(@repository, @queue.branch)
        service.call(entry: @queue_entry, actor: @actor)
      end
    end
  end
end
