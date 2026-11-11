# typed: strict
# frozen_string_literal: true

module GitHub
  module RemoteCache
    class RoundedNumericStalenessObserver
      extend T::Generic
      extend GitHub::RemoteCache::StalenessObserver

      SourceValueType = type_template { { upper: Numeric } }

      sig { override.params(cache_value: SourceValueType, source_value: SourceValueType, context: T::Hash[Symbol, T.untyped]).returns(T::Boolean) }
      def self.stale?(cache_value, source_value, context)
        round_navbar_counter(cache_value) != round_navbar_counter(source_value)
      end

      # We compute staleness based on the rounded values of the cache and database values since that's
      # what we're showing to the user, not the raw values stored in the cache and database. This allows
      # us to benefit from that rounding as we can increase the TTL and get better cache hit rates
      # without significantly affecting staleness.
      sig { params(counter_value: SourceValueType).returns(Numeric) }
      def self.round_navbar_counter(counter_value)
        case counter_value
        when 0..999
          counter_value
        when 1000..5000
          ((counter_value + 50) / 100) * 100
        else
          5001
        end
      end
    end
  end
end
