# typed: true
# frozen_string_literal: true

require "test_helper"

class HookPayloadMergeQueueEntryPayloadTest < GitHub::TestCase
  fixtures do
    @user     = create(:user)
    @dequeuer = create(:user)
    @repo     = create(:repository, owner: @user, from_example: :pull_request_source)

    @queue  = create(:merge_queue, repository: @repo)
  end

  context "when a merge queue entry is added" do
    test "payload is complete" do
      entry = create(:merge_queue_entry, queue: @queue, enqueuer: @user)
      payload = build_hook_payload(
        action: :created,
        merge_queue_entry_id: entry.id,
      ).to_hash

      mq_payload = payload[:merge_queue]
      entry_payload = payload[:merge_queue_entry]

      assert_equal :created, payload[:action]
      assert_equal @user.id, payload[:sender][:id]
      assert_equal @queue.id, mq_payload[:id]
      assert_equal entry.id, entry_payload[:id]
      assert_equal entry.solo?, entry_payload[:is_solo]
    end
  end

  context "when a merge queue entry is deleted" do
    test "payload is complete" do
      entry = create(:merge_queue_entry, queue: @queue, enqueuer: @user)
      message = "test deleted"
      payload = build_hook_payload(
        action: :deleted,
        actor_id: @dequeuer.id,
        merge_queue_entry_id: entry.id,
        merge_queue_id: @queue.id,
        message: message,
        pull_request_id: entry.pull_request_id,
      ).to_hash

      mq_payload = payload[:merge_queue]

      assert_equal :deleted, payload[:action]
      assert_equal @dequeuer.id, payload[:sender][:id]
      assert_equal @queue.id, mq_payload[:id]
      assert_equal payload[:message], message
      assert_equal entry.pull_request_id, payload[:pull_request][:id]
      assert_nil payload[:merge_queue_entry]
    end
  end

  def build_hook_payload(attrs = {})
    defaults = {}

    event = Hook::Event::MergeQueueEntryEvent.new(attrs.reverse_merge(defaults))
    Hook::Payload::MergeQueueEntryPayload.new(event)
  end
end
