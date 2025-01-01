# typed: true
# frozen_string_literal: true

require "test_helper"

class HookEventMergeQueueEntryEventTest < GitHub::TestCase
  include HookEventTestHelper

  fixtures do
    @repo = create(:repository, :org_owned)
    @org = @repo.organization

    @entry = create(:merge_queue_entry)
    @merge_queue = @entry.queue
    @pull_request = @entry.pull_request

    make_trusted_oauth_apps_owner

    @actor    = create(:user)
    @dequeuer = create(:user)
  end

  setup do
    GitHub.flipper[:merge_queue].enable

    @create_event_args = {
      action: :created,
      merge_queue_entry_id: @entry.id,
    }

    @delete_event_args = {
      action: :deleted,
      actor_id: @dequeuer.id,
      merge_queue_entry_id: @entry.id,
      merge_queue_id: @merge_queue.id,
      message: "test deletion",
      pull_request_id: @entry.pull_request_id,
    }
  end

  test "required attributes" do
    assert_event_required_attributes Hook::Event::MergeQueueEntryEvent, :merge_queue_entry_id, :action
  end

  test "is feature flagged" do
    GitHub.flipper[:merge_queue].disable
    event = build_merge_queue_create_event
    assert Hook::Event::MergeQueueEntryEvent.feature_flagged?, "feature flagged with feature completely disabled"
    assert event.feature_flagged?, "always feature flagged with feature completely disabled"
    refute event.send(:feature_flag_enabled?), "should always be disabled"
  end

  test "builds a merge queue create event" do
    # Ensure it found the data in the database
    event = build_merge_queue_create_event
    assert_equal event.merge_queue, @merge_queue
  end

  # Ensure the target_organization is nil to make the feature flag work
  # as expected
  test "target_organization is nil" do
    event = build_merge_queue_create_event
    assert_nil event.target_organization
  end

  test "a delete event is created correctly" do
    event = build_merge_queue_delete_event
    assert_equal event.action, @delete_event_args[:action]
    assert_equal event.merge_queue, @merge_queue
    assert_equal event.pull_request, @pull_request
    assert_equal event.message, @delete_event_args[:message]
  end

  private

  def build_merge_queue_create_event(options = {})
    Hook::Event::MergeQueueEntryEvent.new(@create_event_args.merge(options))
  end

  def build_merge_queue_delete_event(options = {})
    Hook::Event::MergeQueueEntryEvent.new(@delete_event_args.merge(options))
  end
end
