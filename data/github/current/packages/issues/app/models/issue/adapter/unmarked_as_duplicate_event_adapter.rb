# typed: true
# frozen_string_literal: true

class Issue::Adapter::UnmarkedAsDuplicateEventAdapter < Issue::Adapter::DuplicateEventAdapter
  TYPES = [PlatformTypes::UnmarkedAsDuplicateEvent]

  def initialize(context, event_id:)
    super(context, event_id: event_id, event_name: UNMARKED_AS_DUPLICATE_EVENT)
  end

  sig { override.returns(T.nilable(T::Array[T::Class[T.anything]])) }
  def self.defined_types
    TYPES
  end
end
