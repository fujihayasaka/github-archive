# typed: true
# frozen_string_literal: true

module Platform
  module Scalars
    class CustomPropertyValue < Platform::Scalars::Base
      description "A custom property value can be either a string or an array of strings. All property types support only a single string value, except for the multi-select type, which supports only a string array."

      def self.coerce_input(value, _ctx)
        case value
        when String
          value
        when Array
          value.all?(String) ? value : nil
        else
          nil
        end
      end

      def self.coerce_result(value, _ctx)
        value
      end
    end
  end
end
