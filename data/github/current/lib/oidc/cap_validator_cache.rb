# typed: true
# frozen_string_literal: true

module OIDC
  class CapValidatorCache
    CACHE_KEY_PREFIX = "oidc_refresh_token_cache_"
    PERSISTENT_CACHE_LIFETIME = 1.hour
    EPHEMERAL_CACHE_LIFETIME = 1.hour

    CACHE_RESPONSE_FROM_MEMCACHED = "memcached"
    CACHE_RESPONSE_FROM_KV = "kv"

    sig { params(business: Business, external_identity: ExternalIdentity, client_ip: String).returns(T.nilable([String, String])) }
    def self.get(business, external_identity, client_ip)
      return nil unless enabled?(business)
      key = cache_key(external_identity, client_ip)

      if ephemeral_cache_enabled?(business)
        ephemeral_cache_value = GitHub.cache.get(key)
        return [ephemeral_cache_value, CACHE_RESPONSE_FROM_MEMCACHED] if ephemeral_cache_value&.present?
      end

      kv_cache_value = ExternalIdentities::KV.get(key).value { nil }
      return [kv_cache_value, CACHE_RESPONSE_FROM_KV] if kv_cache_value&.present?

      nil
    end

    sig { params(business: Business, external_identity: ExternalIdentity, client_ip: String, value: String, ephemeral_only: T::Boolean).void }
    def self.write(business, external_identity, client_ip, value, ephemeral_only: false)
      return unless enabled?(business)
      key = cache_key(external_identity, client_ip)

      if ephemeral_cache_enabled?(business)
        ephemeral_set(key, value)
      end

      # if ephemeral_only, we don't want to write to KV
      return if ephemeral_only

      ActiveRecord::Base.connected_to(role: :writing) do
        begin
          ExternalIdentities::KV.set(key, value, expires: PERSISTENT_CACHE_LIFETIME.from_now)
        rescue GitHub::KV::UnavailableError
          # noop, if we can't set the cache we don't want to fail the request
          GitHub.logger.error("KV cache is unavailable",
            {
              "gh.business.name" => business.slug,
              "gh.external_identities.kv.key" => key,
              "gh.external_identities.kv.value" => value,
            }
          )
        end
      end
    end

    def self.cache_key(external_identity, client_ip)
      CACHE_KEY_PREFIX + Digest::SHA256.hexdigest("#{external_identity.id}_#{client_ip}")
    end

    private_class_method def self.enabled?(business)
      return false unless business.present?
      !business.feature_flag_enabled?(:disable_oidc_cap_cache, default: false)
    end

    private_class_method def self.ephemeral_cache_enabled?(business)
      return false unless business.present?
      true
    end

    private_class_method def self.ephemeral_set(key, value)
      GitHub.cache.set(key, value, EPHEMERAL_CACHE_LIFETIME)
      GitHub.regional_caches.each do |_, region_cache|
        region_cache.set(key, value, EPHEMERAL_CACHE_LIFETIME)
      end
    end
  end
end
