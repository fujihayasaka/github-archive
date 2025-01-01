# typed: true
# frozen_string_literal: true

# on the platform side, TimelineEvent is an interface that is a implemented by
# issue events and other timeline items such as cross references
class Issue::Adapter::TimelineEventAdapter < Issue::Adapter::Base
  TYPES = [
    PlatformTypes::TimelineEvent
  ].freeze

  sig { override.returns(T.nilable(T::Array[T::Class[T.anything]])) }
  def self.defined_types
    TYPES
  end
end
