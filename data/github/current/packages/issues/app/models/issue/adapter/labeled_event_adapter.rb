# typed: true
# frozen_string_literal: true

class Issue::Adapter::LabeledEventAdapter < Issue::Adapter::LabelEventAdapter
  TYPES = [PlatformTypes::LabeledEvent]

  def initialize(context, event_id:)
    super(context, event_id: event_id, event_name: LABELED_EVENT)
  end

  sig { override.returns(T.nilable(T::Array[T::Class[T.anything]])) }
  def self.defined_types
    TYPES
  end
end
