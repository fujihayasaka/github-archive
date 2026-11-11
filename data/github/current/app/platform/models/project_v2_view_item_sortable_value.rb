# typed: strict
# frozen_string_literal: true

module Platform
  module Models
    class ProjectV2ViewItemSortableValue < T::Struct
      FLOATING_POINT_REGEX = T.let(/\A-?\d+\.\d+\z/.freeze, Regexp)
      INTEGER_REGEX = T.let(/\A-?\d+\z/.freeze, Regexp)

      const :type, String
      const :value, T.nilable(String)

      # This method is used to convert a simple type or string value to a typed model.
      # The only types supported are simple types that are are a subset of JSON.
      sig { params(raw_value: T.untyped).returns(T.attached_class) }
      def self.from_raw_value(raw_value)
        case raw_value
        when NilClass
          new(type: "null", value: nil)
        when Integer
          new(type: "integer", value: raw_value.to_s)
        when Float, BigDecimal
          new(type: "float", value: raw_value.to_s)
        when String
          if raw_value.match?(FLOATING_POINT_REGEX)
            new(type: "float", value: raw_value)
          elsif raw_value.match?(INTEGER_REGEX)
            new(type: "integer", value: raw_value)
          else
            new(type: "string", value: raw_value)
          end
        else
          # Fallback to a String type in case we don't know what to do with the value.
          new(type: "string", value: raw_value.to_s)
        end
      end
    end
  end
end
