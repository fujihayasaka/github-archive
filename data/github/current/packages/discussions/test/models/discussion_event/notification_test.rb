# typed: true
# frozen_string_literal: true

require "test_helper"

class DiscussionEventNotificationTest < GitHub::TestCase
  include NewsiesHelper

  fixtures do
    @discussion     = create(:discussion)
    @repository     = @discussion.repository
    @closed_event   = create(:discussion_event, :closed, discussion: @discussion)
    @reopened_event = create(:discussion_event, :reopened, discussion: @discussion)
  end

  context "#find_by_id" do
    test "wraps a discussion event" do
      notification = DiscussionEvent::Notification.new(event: @closed_event)
      assert_equal @closed_event, notification.event
    end
  end

  context "#body" do
    test "generates body for closed event" do
      notification = DiscussionEvent::Notification.new(event: @closed_event)
      assert_equal "Closed ##{@discussion.number} as resolved.", notification.body
    end

    test "generates body for reopened event" do
      notification = DiscussionEvent::Notification.new(event: @reopened_event)
      assert_equal "Reopened ##{@discussion.number}.", notification.body
    end

    test "raises NotImplementedError for unsupported event" do
      locked_event = create(:discussion_event)
      notification = DiscussionEvent::Notification.new(event: locked_event)

      assert_raises_with_message(NotImplementedError, "unexpected event type locked") do
        notification.body
      end
    end
  end

  context "#user" do
    test "returns actor from event" do
      notification = DiscussionEvent::Notification.new(event: @closed_event)
      assert_equal @closed_event.actor, notification.user
    end

    test "falls back to discussion author if actor is deleted" do
      @closed_event.actor.destroy!
      notification = DiscussionEvent::Notification.new(event: @closed_event.reload)
      assert_equal @discussion.user, notification.user
    end
  end

  context "#user_id" do
    test "returns actor id from event" do
      notification = DiscussionEvent::Notification.new(event: @closed_event)
      assert_equal @closed_event.actor_id, notification.user_id
    end

    test "falls back to discussion author if actor is deleted" do
      @closed_event.actor.destroy!
      notification = DiscussionEvent::Notification.new(event: @closed_event.reload)
      assert_equal @discussion.user_id, notification.user_id
    end
  end

  context "#message_id" do
    test "generates message id for event" do
      notification = DiscussionEvent::Notification.new(event: @closed_event)
      discussion_message_id = "#{@repository.name_with_display_owner}/repo-discussions/#{@discussion.number}"
      expected = "<#{discussion_message_id}/discussion_event/#{@closed_event.id}@#{GitHub.urls.host_name}>"
      assert_equal expected, notification.message_id
    end
  end
end
