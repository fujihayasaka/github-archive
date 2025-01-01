# typed: strict
# frozen_string_literal: true

module GitHub
  module Config
    module CopilotAPI
      extend T::Sig

      # Locking these key names in as they are most likely stored in the vault so changing them can have
      # an impact in production.
      COPILOT_API_URL_KEY = "COPILOT_API_URL"
      COPILOT_PLATFORM_API_AND_GITHUB_HMAC_SECRET_KEY = "COPILOT_PLATFORM_API_AND_GITHUB_HMAC_SECRET"

      sig { returns(String) }
      def self.api_url
        GitHub.copilot_api_url
      end

      sig { returns(String) }
      def self.hmac_secret
        GitHub.environment.fetch(COPILOT_PLATFORM_API_AND_GITHUB_HMAC_SECRET_KEY, "copilot_platform_api_hmac_very_secret")
      end
    end
  end
end
