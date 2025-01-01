# typed: strict
# frozen_string_literal: true

module Discussions
  class EventComponent < ApplicationComponent
    include HydroHelper

    sig { params(event: DiscussionEvent, timeline: DiscussionTimeline).void }
    def initialize(event:, timeline:)
      @event    = event
      @timeline = timeline
    end

    private

    sig { returns(DiscussionEvent) }
    attr_reader :event

    sig { returns(DiscussionTimeline) }
    attr_reader :timeline

    sig { returns(T::Boolean) }
    def render?
      return true unless event.created_issue?
      event.issue.present? # domain-isolation-query-violation:ignore:packages/issues (SELECT)
    end

    sig { returns(T.nilable(String)) }
    def description
      if event.marked_or_unmarked_answer? || event.verified_or_unverified_answer?
        render(Discussions::MarkedOrUnmarkedAnswerEventDescriptionComponent.new(
          event: event,
          discussion: timeline.discussion,
          timeline: timeline,
        ))
      elsif event.transferred?
        render(Discussions::TransferredEventDescriptionComponent.new(
          event: event,
          timeline: timeline,
        ))
      elsif event.created_issue? && event.issue.present?
        render(Discussions::CreatedIssueEventDescriptionComponent.new(
          event: event,
          timeline: timeline,
        ))
      elsif event.closed?
        typed_reason = Discussion::StateReasonable::CloseReason.deserialize(event.state_reason)
        "as #{typed_reason.serialize}"
      end
    end

    sig { params(event_type: String).returns(String) }
    def discussion_event_verb(event_type)
      case event_type.to_sym
      when :answer_marked
        "marked"
      when :answer_unmarked
        "unmarked"
      when :answer_verified
        "verified"
      when :answer_unverified
        "unverified"
      when :created_issue
        "created issue"
      else
        event_type
      end
    end
  end
end
