# typed: true
# frozen_string_literal: true

module Platform
  module Scalars
    class PreciseDateTime < Platform::Scalars::Base
      description "An ISO-8601 encoded UTC date string with millisecond precision."

      def self.coerce_input(value, context)
        Time.iso8601(value)
      rescue ArgumentError, ::TypeError
        nil
      end

      def self.coerce_result(value, context)
        return nil unless value
        value.to_time.utc.iso8601(3)
      end
    end
  end
end
