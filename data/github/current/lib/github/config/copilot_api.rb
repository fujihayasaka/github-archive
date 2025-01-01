# typed: strict
# frozen_string_literal: true

module GitHub
  module Config
    module CopilotAPI

      # Locking these key names in as they are most likely stored in the vault so changing them can have
      # an impact in production.
      COPILOT_PLATFORM_API_AND_GITHUB_HMAC_SECRET_KEY = "COPILOT_PLATFORM_API_AND_GITHUB_HMAC_SECRET"
      COPILOT_DEVELOPER_HMAC_SECRET_KEY = "COPILOT_PLATFORM_API_AND_COPILOT_DEVELOPER_HMAC_SECRET"

      sig { returns(String) }
      def self.hmac_secret
        GitHub.environment.fetch(COPILOT_PLATFORM_API_AND_GITHUB_HMAC_SECRET_KEY, "copilot_platform_api_hmac_very_secret")
      end

      sig { returns(String) }
      def self.copilot_developer_hmac_secret
        GitHub.environment.fetch(COPILOT_DEVELOPER_HMAC_SECRET_KEY, "copilot_developer_hmac_very_secret")
      end
    end
  end
end
