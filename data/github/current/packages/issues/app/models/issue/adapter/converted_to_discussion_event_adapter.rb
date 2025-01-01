# typed: true
# frozen_string_literal: true

class Issue::Adapter::ConvertedToDiscussionEventAdapter < Issue::Adapter::IssueEventAdapter
  TYPES = [
    PlatformTypes::ConvertedToDiscussionEvent
  ].freeze

  CONVERTED_EVENT = "ConvertedToDiscussionEvent"

  attr_reader :discussion

  def initialize(context, event_id:)
    super(context, event_id: event_id, event_name: CONVERTED_EVENT)
    discussion = context.converted_discussions_by_event_id[event_id]
    @discussion = Issue::Adapter::ConvertedToDiscussionEventDiscussionAdapter.new(
      context,
      discussion: discussion,
    ) if discussion
  end

  sig { override.returns(T.nilable(T::Array[T::Class[T.anything]])) }
  def self.defined_types
    TYPES
  end
end
