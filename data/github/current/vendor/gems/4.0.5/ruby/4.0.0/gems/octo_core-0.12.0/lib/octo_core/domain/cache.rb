# typed: strict
# frozen_string_literal: true

require_relative "cache/cacheable"
require_relative "cache/cacheable/dirtyable"
require_relative "cache/telemetry_reporter"

module OctoCore
  module Domain
    class Cache
      extend T::Sig
      extend T::Helpers

      sig { params(domain: String, accessor: String, telemetry_reporter: T.nilable(TelemetryReporter)).void }
      def initialize(domain:, accessor:, telemetry_reporter: nil)
        @domain = domain
        @accessor = accessor
        @reporter = telemetry_reporter
        @cache = T.let({}, T::Hash[Symbol, T::Hash[String, T.nilable(Object)]])
        @id_cache = T.let({}, T::Hash[Integer, T.nilable(Cacheable)])
      end

      sig { returns(String) }
      attr_reader :domain

      sig { returns(String) }
      attr_reader :accessor

      sig { returns(T.nilable(TelemetryReporter)) }
      attr_reader :reporter

      sig { params(method_name: Symbol, args: T.anything, kwargs: T.anything, block: T.proc.returns(Object)).returns(T.nilable(Object)) }
      def fetch(method_name, *args, **kwargs, &block)
        @cache[method_name] ||= {}
        method_cache = T.must(@cache[method_name])
        key = T.unsafe(self).key(*args, **kwargs)

        if method_cache.include?(key)
          value = method_cache[key]
          if value.nil? || !value.is_a?(Cacheable)
            reporter&.report_attempt(method_name:, hit: true, key_count: method_cache.keys.size)
            return value
          end

          if @id_cache.key?(value.id)
            reporter&.report_attempt(method_name:, hit: true, key_count: method_cache.keys.size)
            return T.cast(value.duplicate, Object)
          else
            method_cache.delete(key)
          end
        end

        result = block.call
        @id_cache[result.id] = result if result.is_a?(Cacheable)
        method_cache[key] = result
        reporter&.report_attempt(method_name:, hit: false, key_count: method_cache.keys.size)
        result
      end

      sig { params(id: Integer, block: T.proc.returns(T.nilable(Cacheable))).returns(T.nilable(Cacheable)) }
      def fetch_by_id(id, &block)
        cache_hit = true
        result = if @id_cache.key?(id)
                   value = @id_cache[id]
                   value&.duplicate
        else
          cache_hit = false
          @id_cache[id] = block.call
        end

        reporter&.report_id_attempt(hit: cache_hit, key_count: @id_cache.keys.size)

        result
      end

      sig { params(cacheable: Cacheable).void }
      def dirty(cacheable:)
        @id_cache.delete(cacheable.id)
        nil
      end

      sig { params(method_name: Symbol).void }
      def clear(method_name:)
        @cache.delete(method_name)
        nil
      end

      sig { params(args: T.untyped, kwargs: T.untyped).returns(String) }
      def key(*args, **kwargs)
        # This is a temporary solution to avoid cache key collisions between tenants.
        # In the future we expect domain singletons/identity context to be tenant-aware
        [args.inspect, kwargs.inspect, nil].hash.to_s
      end
    end
  end
end
