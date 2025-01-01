# typed: true
# frozen_string_literal: true

class Issue::Adapter::RemovedFromProjectEventAdapter < Issue::Adapter::ProjectEventAdapter
  TYPES = [PlatformTypes::RemovedFromProjectEvent]

  def initialize(context, event_id:)
    super(context, event_id: event_id, event_name: REMOVED_FROM_PROJECT)
  end

  sig { override.returns(T.nilable(T::Array[T::Class[T.anything]])) }
  def self.defined_types
    TYPES
  end
end
