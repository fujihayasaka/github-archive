# typed: true
# frozen_string_literal: true

require "test_helper"

class HookMergeGroupPayloadTest < GitHub::TestCase
  fixtures do
    @integration = create :integration
    @queue = create(:merge_queue)
    @queue_entry = create(
      :merge_queue_entry,
      queue: @queue,
      head_sha: "0" * 40,
      base_sha: "0" * 40,
      head_ref: "example-head-ref",
    )
    @pull_request = @queue_entry.pull_request
  end

  context "checks_requested" do
    test "serializes a MergeQueueEntry" do
      event = Hook::Event::MergeGroupEvent.new(
        merge_group_entry_id: @queue_entry.id,
        action: :checks_requested,
        actor_id: @queue_entry.enqueuer.id,
      )

      payload = Hook::Payload::MergeGroupPayload.new(event)

      hash = payload.to_hash
      assert_equal :checks_requested, hash[:action]
      assert_equal @queue.repository.id, hash[:repository][:id]
      assert_equal @queue_entry.head_sha, hash[:merge_group][:head_sha]
      assert_equal @queue_entry.qualified_head_ref, hash[:merge_group][:head_ref]
      assert_equal @queue_entry.base_sha, hash[:merge_group][:base_sha]
      assert_equal "refs/heads/#{@queue_entry.pull_request.base_ref}", hash[:merge_group][:base_ref]
      assert_equal @queue_entry.enqueuer.login, hash[:sender][:login]
      # head_commit is expected to be nil because we don't test with an actual repository here.
      # merge_group_hook_test.rb tests this behaves as expected and verifies a non-nil value.
      assert_nil hash[:merge_group][:head_commit]
    end
  end

  context "destroyed" do
    test "serailizes a group that no longer exists in the database" do
      event = Hook::Event::MergeGroupEvent.new(
        action: :destroyed,
        destroyed_reason: "dequeued",
        actor_id: @queue_entry.enqueuer.id,
        merge_group_props: {
          "pull_request_id" => @pull_request.id,
          "qualified_head_ref" => "refs/heads/merge-queue-example",
          "head_sha" => "0" * 40,
          "base_sha" => "b" * 40,
        }
      )

      payload = Hook::Payload::MergeGroupPayload.new(event)

      hash = payload.to_hash
      assert_equal :destroyed, hash[:action]
      assert_equal "dequeued", hash[:reason]
      assert_equal @pull_request.repository.id, hash[:repository][:id]
      assert_equal "0" * 40, hash[:merge_group][:head_sha]
      assert_equal "refs/heads/merge-queue-example", hash[:merge_group][:head_ref]
      assert_equal "b" * 40, hash[:merge_group][:base_sha]
      assert_equal "refs/heads/#{@pull_request.base_ref}", hash[:merge_group][:base_ref]
      assert_equal @queue_entry.enqueuer.login, hash[:sender][:login]
      # head_commit is expected to be nil because we don't test with an actual repository here.
      # merge_group_hook_test.rb tests this behaves as expected and verifies a non-nil value.
      assert_nil hash[:merge_group][:head_commit]
    end
  end
end
