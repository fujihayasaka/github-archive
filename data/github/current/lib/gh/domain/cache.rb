# typed: strict
# frozen_string_literal: true

require_relative "cache/cachable"
require_relative "cache/cachable/dirtyable"

module GH
  module Domain
    class Cache
      extend T::Helpers

      sig { params(domain: String, accessor: String, registered_domain_namespace: T.nilable(Module)).void }
      def initialize(domain:, accessor:, registered_domain_namespace:)
        @domain = domain
        @accessor = accessor
        @registered_domain_namespace = registered_domain_namespace
        @cache = T.let({}, T::Hash[Symbol, T::Hash[String, T.nilable(Object)]])
        @id_cache = T.let({}, T::Hash[Integer, T.nilable(Cachable)])
      end

      sig { returns(String) }
      attr_reader :domain

      sig { returns(String) }
      attr_reader :accessor

      sig { returns(T.nilable(Module)) }
      attr_reader :registered_domain_namespace

      sig { params(method_name: Symbol, args: T.anything, kwargs: T.anything, block: T.proc.returns(Object)).returns(T.nilable(Object)) }
      def fetch(method_name, *args, **kwargs, &block)
        @cache[method_name] ||= {}
        method_cache = T.must(@cache[method_name])
        key = T.unsafe(self).key(*args, **kwargs)

        if method_cache.include?(key)
          value = method_cache[key]
          if value.nil? || !value.is_a?(Cachable)
            dogstats(metric_name: "method_cache", key_count: method_cache.keys.size, cache_hit: true, method_name: method_name)
            return value
          end

          if @id_cache.key?(value.id)
            dogstats(metric_name: "method_cache", key_count: method_cache.keys.size, cache_hit: true, method_name: method_name)
            return T.cast(value.duplicate, Object)
          else
            method_cache.delete(key)
          end
        end

        result = block.call
        @id_cache[result.id] = result if result.is_a?(Cachable)
        method_cache[key] = result
        dogstats(metric_name: "method_cache", key_count: method_cache.keys.size, cache_hit: false, method_name: method_name)
        result
      end

      sig { params(id: Integer, block: T.proc.returns(T.nilable(Cachable))).returns(T.nilable(Cachable)) }
      def fetch_by_id(id, &block)
        cache_hit = true
        result = if @id_cache.key?(id)
          value = @id_cache[id]
          value&.duplicate
        else
          cache_hit = false
          @id_cache[id] = block.call
        end

        dogstats(metric_name: "id_cache", key_count: @id_cache.keys.size, cache_hit:)

        result
      end

      sig { params(cachable: Cachable).void }
      def dirty(cachable:)
        GH::Domain::Registration.all_domains_for(T.must(registered_domain_namespace)).each do |domain|
          domain.cache.localized_dirty(id: cachable.id)
        end
        nil
      end

      # update this?
      sig { params(id: Integer).void }
      def dirty_id(id)
        GH::Domain::Registration.all_domains_for(T.must(registered_domain_namespace)).each do |domain|
          domain.cache.localized_dirty(id:)
        end
        nil
      end

      sig { params(method_name: Symbol).void }
      def clear(method_name:)
        GH::Domain::Registration.all_domains_for(T.must(registered_domain_namespace)).each do |domain|
          domain.cache.localized_clear(method_name:)
        end
        nil
      end

      sig { params(args: T.untyped, kwargs: T.untyped).returns(String) }
      def key(*args, **kwargs)
        # This is a temporary solution to avoid cache key collisions between tenants.
        # In the future we expect domain singletons/identity context to be tenant-aware
        [args.inspect, kwargs.inspect, GitHub::CurrentTenant.get.try(:id)].hash.to_s
      end

      sig { params(metric_name: String, key_count: Integer, cache_hit: T::Boolean, method_name: T.nilable(Symbol)).void }
      def dogstats(metric_name:, key_count:, cache_hit:, method_name: nil)
        tags = [
          "domain:#{domain}",
          "accessor:#{accessor}",
          "hit:#{cache_hit}",
        ]
        tags << "method:#{method_name}" if method_name
        GitHub.dogstats.count("domain.call.#{metric_name}", key_count, tags:)
      end

      sig { params(id: Integer).void }
      def localized_dirty(id:)
        @id_cache.delete(id)
        nil
      end

      sig { params(method_name: Symbol).void }
      def localized_clear(method_name:)
        @cache.delete(method_name)
        nil
      end
    end
  end
end
