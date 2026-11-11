# typed: strict
# frozen_string_literal: true

require "google/protobuf/wrappers_pb"

module GitHub
  module Protobuf
    # Helpers for wrapping plain Ruby values in the `google.protobuf` well-known
    # wrapper messages, returning `nil` when the value is absent so the field is
    # left unset on the proto.
    #
    #   GitHub::Protobuf::Wrappers.int32_value(42)
    module Wrappers
      sig { params(value: T.nilable(String)).returns(T.nilable(Google::Protobuf::StringValue)) }
      def self.str_value(value)
        return nil if value.nil?

        Google::Protobuf::StringValue.new(value: value)
      end

      sig { params(value: T.nilable(Integer)).returns(T.nilable(Google::Protobuf::Int32Value)) }
      def self.int32_value(value)
        return nil if value.nil?

        Google::Protobuf::Int32Value.new(value: value)
      end

      sig { params(value: T.nilable(T::Boolean)).returns(T.nilable(Google::Protobuf::BoolValue)) }
      def self.bool_value(value)
        return nil if value.nil?

        Google::Protobuf::BoolValue.new(value: value)
      end
    end
  end
end
