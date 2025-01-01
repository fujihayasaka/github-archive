# frozen_string_literal: true

module AdvisoryDB
  module Config
    module Capi
      def self.copilot_api_hmac_key
        ENV.fetch("CLIENT_SECRETS_ADVISORYDB_PREDICTOR", "")
      end

      def self.copilot_api_hmac_dev_key
        ENV.fetch("CLIENT_SECRETS_ADVISORYDB_PREDICTOR_DEV", "")
      end

      def self.capi_secret
        Rails.env.production? ? copilot_api_hmac_key : copilot_api_hmac_dev_key
      end

      def self.capi_integration_id
        integration_suffix = Rails.env.production? ? "" : "-dev"
        "advisorydb-predictor#{integration_suffix}"
      end

      def self.chat_completion_url
        "https://api.githubcopilot.com/chat/completions"
      end

      def self.max_retries
        7
      end
    end
  end
end
