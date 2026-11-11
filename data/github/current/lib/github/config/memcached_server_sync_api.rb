# typed: strict
# frozen_string_literal: true

module GitHub
  module Config
    module MemcachedServerSyncAPI
      FALLBACK_HMAC_SECRETS = "internal_memcached_servers_api_hmac_very_secret"

      sig { returns(T::Array[String]) }
      def self.hmac_secrets
        GitHub.environment.fetch("MEMCACHED_SERVER_SYNC_API_HMAC_SECRETS", FALLBACK_HMAC_SECRETS).split
      end
    end
  end
end
