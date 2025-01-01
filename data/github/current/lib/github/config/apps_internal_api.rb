# typed: strict
# frozen_string_literal: true

module GitHub
  module Config
    module AppsInternalAPI
      extend T::Sig

      sig { returns(String) }
      def self.api_url
        GitHub::AppEnvironment.development? ? "http://api.github.localhost" : "https://api.github.com"
      end

      sig { returns(T::Array[String]) }
      def self.hmac_secrets
        GitHub.environment.fetch("APPS_PLATFORM_API_HMAC_SECRET", "internal_apps_api_hmac_very_secret").split
      end
    end
  end
end
