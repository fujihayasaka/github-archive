# typed: strict
# frozen_string_literal: true

module GitHub
  module RemoteCache::Preset
    extend T::Helpers
    extend T::Generic
    abstract!

    CachedType = type_member

    sig do
      params(
        force_refresh: T::Boolean,
        block: T.proc.returns(CachedType)
      ).returns(CachedType)
    end
    def fetch(force_refresh: false, &block)
      cache_client.fetch(
        cache_key_name: cache_key_name,
        cache_key_id: build_cache_key_id,
        ttl: ttl,
        enabled: enabled?,
        fallback: fallback,
        resilience_error_types: resiliency_error_types,
        serializer: serializer,
        shadow: shadow?,
        force_refresh: force_refresh,
        &block
      )
    end

    sig { params(event: T.nilable(String)).void }
    def invalidate(event = nil)
      cache_client.invalidate(
        cache_key_name: cache_key_name,
        cache_key_id: build_cache_key_id,
        event: event
      )
    end

    sig { abstract.returns(Symbol) }
    def cache_key_name; end

    sig { abstract.returns(String) }
    def cache_key_id; end

    sig { abstract.returns(T.any(T.proc.params(value: T.untyped).returns(Integer), Integer)) }
    def ttl; end

    sig { abstract.returns(T::Boolean) }
    def enabled?; end

    # how to handle nilable as an option?
    sig { abstract.returns(CachedType) }
    def fallback; end

    sig { abstract.returns(T::Array[T.class_of(StandardError)]) }
    def resiliency_error_types; end

    sig { abstract.returns(GitHub::RemoteCache::Serializer[CachedType]) }
    def serializer; end

    sig { abstract.returns(T::Boolean) }
    def shadow?; end

    private

    sig { abstract.returns(GitHub::RemoteCache::Client) }
    def cache_client; end

    sig { returns(String) }
    def build_cache_key_id
      cache_key_id
    rescue => e
      GitHub::RemoteCache::Client::NIL_CACHE_KEY_ID
    end
  end
end
