# typed: true
# frozen_string_literal: true

module Platform
  module Scalars
    # Very similar to DateTime but does not coerce result to UTC before
    # converting to ISO8601 representation
    class GitTimestamp < Platform::Scalars::Base
      description "An ISO-8601 encoded date string. Unlike the DateTime type, GitTimestamp is not converted in UTC."

      def self.coerce_input(value, context)
        begin
          Time.iso8601(value)
        rescue ArgumentError, ::TypeError
        end
      end

      def self.coerce_result(value, context)
        value.iso8601
      end
    end
  end
end
