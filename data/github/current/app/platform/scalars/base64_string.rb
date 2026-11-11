# typed: true
# frozen_string_literal: true

module Platform
  module Scalars
    class Base64String < Platform::Scalars::Base
      description "A (potentially binary) string encoded using base64."

      def self.coerce_input(value, context)
        Base64.strict_decode64(value)
      rescue ArgumentError
        raise Platform::Errors::Coercion, "Invalid Base64: #{value.inspect}"
      end

      def self.coerce_result(value, context)
        return nil if value.nil?
        Base64.strict_encode64(value)
      end
    end
  end
end
