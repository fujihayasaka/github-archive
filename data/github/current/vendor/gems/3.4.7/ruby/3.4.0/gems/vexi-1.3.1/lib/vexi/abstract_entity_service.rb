# frozen_string_literal: true
#              

require "resilient/circuit_breaker"
require "vexi/errors/circuit_breaker_open_error"


module Vexi
  # Public: Vexi service is an abstract base class. It has a generic get to fetch entities from the adapter or cache.
  class AbstractEntityService
    extend T::Generic

    EntityType = type_member { { upper: Entity } } # Makes the `Service` class generic

    def initialize(adapter, cache_config = nil, adapter_breaker = nil, cache_breaker = nil)
      @adapter =      (adapter         )
      @adapter_breaker =      (adapter_breaker                                      )
      @cache_config =      (cache_config                        )
      @cache_breaker =      (cache_breaker                                      )
      @memoization_enabled =      (false            )
      @memoized_entities =      ({}                             )
    end

    def entity_type; end

    def entity_type_name; end

    def memoize=(value)
      @memoized_entities.clear
      @memoization_enabled = value
    end

    def mget(names, fetch_directly_from_adapter: false, cache_without_expiry: false, raise_on_cache_breaker_open: true, _allow_context_overrides: false, instrumentation_context: InstrumentationContext.new)
      return [] if names.empty?

      entities_to_fetch =      (names                  )
      instrumentation_context[:"#{entity_type_name}.fetch_directly_from_adapter"] = fetch_directly_from_adapter

      entities = get_entities_from_memoization(entities_to_fetch, fetch_directly_from_adapter)
      instrumentation_context[:"#{entity_type_name}.memoization.fetch"] = {
        entities_count: entities.size
      }
      entities = entities
      entities_to_fetch -= entities.map(&:name)

      return entities if entities_to_fetch.empty?

      cached_entities = instrumentation_context.instrument_timing(:"#{entity_type_name}.cache.fetch") do |properties|
        begin
          result = get_entities_from_cache(entities_to_fetch, fetch_directly_from_adapter, instrumentation_context)
          properties[:entities_count] = result.size
          result
        rescue Errors::CircuitBreakerOpenError
          raise if raise_on_cache_breaker_open
          []
        rescue StandardError => e
          instrumentation_context.instrument_error(:"#{entity_type_name}.cache.fetch.error", e, message: "Error fetching entities from cache")
          []
        end
      end

      entities = entities.concat(cached_entities)
      entities_to_fetch -= cached_entities.map(&:name)

      return entities if entities_to_fetch.empty?

      entities.concat(get_entities_from_adapter(entities_to_fetch, cache_without_expiry, instrumentation_context))
    end

    def get(name, fetch_directly_from_adapter: false, cache_without_expiry: false, raise_on_cache_breaker_open: true, _allow_context_overrides: false, instrumentation_context: InstrumentationContext.new)
      entity = get_entity_from_memoization(name, fetch_directly_from_adapter)
      instrumentation_context[:"#{entity_type_name}.memoization.fetch"] = {
        entities_count: entity ? 1 : 0
      }

      return entity if entity

      cached_entity = instrumentation_context.instrument_timing(:"#{entity_type_name}.cache.fetch") do |properties|
        begin
          result = get_entity_from_cache(name, fetch_directly_from_adapter, instrumentation_context)
          properties[:entities_count] = result ? 1 : 0
          result
        rescue Errors::CircuitBreakerOpenError
          raise if raise_on_cache_breaker_open
          nil
        rescue StandardError => e
          instrumentation_context.instrument_error(:"#{entity_type_name}.cache.fetch.error", e, message: "Error fetching entity from cache")
          nil
        end
      end

      return cached_entity if cached_entity

      get_entity_from_adapter(name, cache_without_expiry, instrumentation_context)
    end

    def get_cache_key(name); end

    def get_entity_responses(names); end

    def get_default_entity_instance(name); end

    def get_cache_keys(names)
      names.map { |name| get_cache_key(name) }
    end

    def get_entities_from_memoization(entity_names, fetch_directly_from_adapter)
      return [] unless @memoization_enabled
      return [] if fetch_directly_from_adapter

      entity_names.each_with_object([]) do |entity_name, fetched_entities|
        entity = @memoized_entities[entity_name]
        next unless entity

        fetched_entities.push(entity)
      end
    end

    def get_entity_from_memoization(entity_name, fetch_directly_from_adapter)
      return nil unless @memoization_enabled
      return nil if fetch_directly_from_adapter

      @memoized_entities[entity_name]
    end

    def get_entities_from_cache(entity_names, fetch_directly_from_adapter, instrumentation_context)
      return [] if fetch_directly_from_adapter
      return [] if @cache_config.nil?
      return [] if entity_names.empty?

      cached_entities =      ([]                      )
      circuit_breaker_run(@cache_breaker, instrumentation_context, "cache.fetch") do
        cached_entities = @cache_config.cache.mget(get_cache_keys(entity_names))
      end

      # If memoization is enabled, add entities retrieved from cache to memoized entities
      cached_entities.each do |entity|
        if @memoization_enabled
          @memoized_entities[entity.name] = entity
        end
      end

      cached_entities
    end

    def get_entity_from_cache(entity_name, fetch_directly_from_adapter, instrumentation_context)
      return nil if fetch_directly_from_adapter
      return nil if @cache_config.nil?

      cached_entity =      (nil                       )
      circuit_breaker_run(@cache_breaker, instrumentation_context, "cache.fetch") do
        cached_entity = @cache_config.cache.get(get_cache_key(entity_name))
      end

      # If memoization is enabled, add entity retrieved from cache to memoized entities
      @memoized_entities[cached_entity.name] = cached_entity if @memoization_enabled && cached_entity

      cached_entity
    end

    def get_entities_from_adapter(entity_names, cache_without_expiry, instrumentation_context)
      # Fetch entities from the adapter and cache them if a cache is present
      entities =      ([]                      )
      entities_to_cache =      ({}                             )

      responses =      ([]                             )
      instrumentation_context.instrument_timing(:"#{entity_type_name}.adapter.fetch") do |properties|
        circuit_breaker_run(@adapter_breaker, instrumentation_context, "adapter.fetch") do
          responses = get_entity_responses(entity_names)
          properties[:entities_count] = responses.size
        end
      end

      responses.each do |response|
        next unless response.error.nil?
        next unless response.entity

        entity =       (response.entity            )
        entities.push(entity)

        entity_name = entity.name
        entities_to_cache[get_cache_key(entity_name)] = entity
      end

      if @cache_config
        cache_ttl = cache_without_expiry ? Cache::TTL_NEVER_EXPIRE : @cache_config.ttl
        cache_mset(entities_to_cache, cache_ttl, instrumentation_context, :"#{entity_type_name}.cache.mset")
      end

      # Any entities that were not found in the response should be created as default instances and cached
      not_found_entity_names = entity_names - entities.map(&:name)
      if not_found_entity_names.any?
        not_found_entities_to_cache = not_found_entity_names.each_with_object({}) do |name, obj|
          entity = get_default_entity_instance(name)
          entity.not_found = true
          entities.push(entity)
          obj[get_cache_key(name)] = entity
        end
        if @cache_config
          cache_mset(not_found_entities_to_cache, @cache_config.not_found_ttl, instrumentation_context, :"#{entity_type_name}.cache.not_found.mset")
        end
      end

      if @memoization_enabled
        entities.each do |entity|
          @memoized_entities[entity.name] = entity
        end
      end

      entities
    end

    def get_entity_from_adapter(entity_name, cache_without_expiry, instrumentation_context)
      # Fetch entity from the adapter and cache them if a cache is present
      responses =      ([]                             )
      instrumentation_context.instrument_timing(:"#{entity_type_name}.adapter.fetch") do |properties|
        circuit_breaker_run(@adapter_breaker, instrumentation_context, "adapter.fetch") do
          responses = get_entity_responses([entity_name])
          properties[:entities_count] = responses.size
        end
      end

      cache_key = get_cache_key(entity_name)

      # Any entities that were not found in the response should be created as default instances and cached
      first_response = responses.first
      entity = first_response.nil? || !first_response.entity ? get_default_entity_instance(entity_name) :       (first_response.entity            )

      if @cache_config
        # Entities that were not found should be cached with a different TTL
        ttl = if first_response.nil? || !first_response.entity
                @cache_config.not_found_ttl
              else
                cache_without_expiry ? Cache::TTL_NEVER_EXPIRE : @cache_config.ttl
              end

        instrumentation_context.instrument_timing(:"#{entity_type_name}.cache.set") do |properties|
          begin
            circuit_breaker_run(@cache_breaker, instrumentation_context, "cache.set") do
              @cache_config.cache.set(cache_key, entity, ttl)
              properties[:cache_ttl] = ttl
            end
          rescue Errors::CircuitBreakerOpenError
          rescue StandardError => e
            instrumentation_context.instrument_error(:"#{entity_type_name}.cache.set.error", e, message: "Error setting entity in cache")
          end
        end
      end

      if @memoization_enabled
        @memoized_entities[entity.name] = entity
      end

      entity
    end

    private

    def circuit_breaker_run(breaker, instrumentation_context, operation, &block)
      if breaker.nil?
        yield
      elsif breaker.allow_request?
        begin
          yield
          breaker.success
        rescue
          breaker.failure
          raise
        end
      else
        instrumentation_context[:"#{entity_type_name}.#{operation}.circuit_breaker_open"] = true
        raise Errors::CircuitBreakerOpenError.new(entity_type_name, operation)
      end
    end

    def cache_mset(entities_to_cache, cache_ttl, instrumentation_context, operation)
      return if @cache_config.nil?

      instrumentation_context.instrument_timing(operation) do |properties|
        begin
          circuit_breaker_run(@cache_breaker, instrumentation_context, "cache.mset") do
            @cache_config.cache.mset(entities_to_cache, cache_ttl)
          end
          properties[:entities_count] = entities_to_cache.size
          properties[:cache_ttl] = cache_ttl
        rescue Errors::CircuitBreakerOpenError
        rescue StandardError => e
          instrumentation_context.instrument_error(:"#{operation}.error", e, message: "Error setting entities in cache")
        end
      end
    end
  end
end
