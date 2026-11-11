# typed: true
# frozen_string_literal: true

module Platform
  module Scalars
    class Date < Platform::Scalars::Base
      description "An ISO-8601 encoded date string."

      def self.coerce_input(value, context)
        ::Date.iso8601(value)
      rescue ArgumentError, ::TypeError
        nil
      end

      def self.coerce_result(value, context)
        if value
          (value.try(:utc) || value).to_date.iso8601
        end
      end
    end
  end
end
