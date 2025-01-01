# typed: strict
# frozen_string_literal: true

class DiscussionEvent::Notification
  extend T::Sig
  include GitHub::UserContent

  # Public: Find a DiscussionEvent and create a DiscussionEvent::Notification wrapping it.
  #         This is typically used by Newsies to actually deliver notifications.
  sig { params(id: Integer).returns(T.nilable(DiscussionEvent::Notification)) }
  def self.find_by_id(id) # rubocop:disable GitHub/FindByDef
    issue_event = DiscussionEvent.find_by(id: id)
    return unless issue_event.present?
    new(event: issue_event)
  end

  sig { params(event: DiscussionEvent).void }
  def initialize(event:)
    @event = event
  end

  sig { returns(DiscussionEvent) }
  attr_reader :event

  delegate :actor, :discussion, :id, :repository, :async_repository, :state_reason, to: :event
  delegate :permalink, to: :discussion

  # Used by newsies
  alias :notifications_thread :discussion
  alias :notifications_list :repository
  alias :entity :repository
  alias :async_entity :async_repository

  # Public: The notification body.
  sig { returns(String) }
  def body
    body = "#{action} ##{discussion.number}"

    if include_state_reason?
      body << " as #{event.state_reason}"
    end

    body << "."
    body
  end

  # Public: A unique message ID for use with newsies for email notifications.
  sig { returns(String) }
  def message_id
    discussion_message_id = "#{repository.name_with_display_owner}/repo-discussions/#{discussion.number}"
    "<#{discussion_message_id}/discussion_event/#{id}@#{GitHub.urls.host_name}>"
  end

  # Public: The user sending this notification.
  sig { returns(T.nilable(User)) }
  def user
    actor || discussion.user
  end
  alias :notifications_author :user

  # Public: The ID of the user sending this notification.
  sig { returns(T.nilable(Integer)) }
  def user_id
    user&.id
  end

  private

  sig { returns(String) }
  def action
    case event.event_type
    when "reopened"
      "Reopened"
    when "closed"
      "Closed"
    else
      raise NotImplementedError, "unexpected event type #{event.event_type}"
    end
  end

  sig { returns(T::Boolean) }
  def include_state_reason?
    return false unless state_reason.present?
    state_reason != Discussion::StateReasonable::StateReason::Reopened.serialize
  end
end
