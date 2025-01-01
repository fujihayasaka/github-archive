# typed: strict
# frozen_string_literal: true

module Codespaces
  module Dials
    class ExtendedRateLimitMaxOperations < Codespaces::Dial

      validates :value, numericality: { only_integer: true, greater_than_or_equal_to: 5 }

      sig { override.returns(String) }
      def key
        "codespaces_extended_rate_limit_max_operations"
      end

      sig { override.returns(Integer) }
      def default_value
        5
      end

      sig { override.returns(String) }
      def description
        "We have a static rate limit for creating and resuming codespaces, allowing 5 total per 1 minute. This value sets the maximum create and resume operations for a longer-term rate limit, with the time window configured with the complementary `codespaces_extended_rate_limit_duration_minutes`. Values must be >= 5 to avoid conflicting with the static rate limit."
      end

      private

      sig { params(value: String).returns(Integer) }
      def transform_value_to_use(value)
        value.to_i
      end
    end
  end
end
