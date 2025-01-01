# typed: strict
# frozen_string_literal: true

module Codespaces
  module Dials
    class ExtendedRateLimitDurationMinutes < Codespaces::Dial

      validates :value, numericality: { only_integer: true, greater_than_or_equal_to: 0 }

      sig { override.returns(String) }
      def key
        "codespaces_extended_rate_limit_duration_minutes"
      end

      sig { override.returns(Integer) }
      def default_value
        0
      end

      sig { override.returns(String) }
      def description
        "We have a static rate limit for creating and resuming codespaces, allowing 5 total per 1 minute. This value sets the time window for a longer-term rate limit, with the number of actions allowed in that time window configured with the complementary `codespaces_extended_rate_limit_max_operations`. When this value is set to 0, the rate limit will not be enforced. When values are changed, existing time windows will still need to expire in Redis, so in an incident scenario, it's better to be more aggressive and use shorter durations."
      end

      private

      sig { params(value: String).returns(Integer) }
      def transform_value_to_use(value)
        value.to_i
      end
    end
  end
end
