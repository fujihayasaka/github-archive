# typed: strict
# frozen_string_literal: true

module GitHub
  module Config
    module AppsPrivilegedAPI

      FALLBACK_HMAC_SECRET = "internal_apps_api_hmac_very_secret"

      sig { returns(String) }
      def self.api_url
        GitHub::AppEnvironment.development? ? "http://api.github.localhost" : "https://api.github.com"
      end

      sig { returns(T::Array[String]) }
      def self.hmac_secrets
        GitHub.environment.fetch("APPS_PLATFORM_API_HMAC_SECRET", FALLBACK_HMAC_SECRET).split
      end
    end
  end
end
