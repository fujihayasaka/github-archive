# typed: strict
# frozen_string_literal: true

module GitHub
  module RemoteCache
    class RoundedNumericSerializer < NumericSerializer
      extend T::Generic
      extend GitHub::RemoteCache::Serializer

      CachedType = type_template { { fixed: Numeric } }

      sig { override.params(cached_value: CachedType, db_value: CachedType).returns(GitHub::RemoteCache::Comparison) }
      def self.compare(cached_value, db_value)
        equality = round_navbar_counter(cached_value) <=> round_navbar_counter(db_value)
        diff = equality.zero? ? [] : [[equality]]
        GitHub::RemoteCache::Comparison.new(diff)
      end

      # We compute staleness based on the rounded values of the cache and database values since that's
      # what we're showing to the user, not the raw values stored in the cache and database. This allows
      # us to benefit from that rounding as we can increase the TTL and get better cache hit rates
      # without significantly affecting staleness.
      sig { params(counter_value: CachedType).returns(Numeric) }
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
