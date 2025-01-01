# typed: true
# frozen_string_literal: true

# ProtobufsHelper provides utility methods for using Google::Protobuf wrapper classes.
module Events
  module ProtobufsHelper
    # Public: Wraps a value in a Google::Protobuf wrapper class. Returns nil if the value is nil.
    # This only works for classes that use a `value` attribute.
    sig { params(wrapper_class: T.untyped, value: T.anything).returns(T.untyped) }
    def self.wrap_value(wrapper_class, value)
      return nil unless value
      wrapper_class.new(value: value)
    end

    # Public: Wraps a value in a Google::Protobuf::Timestamp wrapper class. Returns nil if the value is nil.
    sig { params(time: T.nilable(ActiveSupport::TimeWithZone)).returns(T.nilable(Google::Protobuf::Timestamp)) }
    def self.wrap_timestamp(time)
      return nil unless time
      Google::Protobuf::Timestamp.new(seconds: time.to_i)
    end
  end
end
