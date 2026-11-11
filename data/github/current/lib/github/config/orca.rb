# typed: true
# frozen_string_literal: true

module GitHub
  module Config
    module Orca
      ORCA_BASE_URL = "ORCA_BASE_URL"
      ORCA_HMAC_KEY = "ORCA_HMAC_KEY"

      def orca_base_url=(url)
        @orca_base_url = url
      end

      def orca_base_url
        if GitHub.employee_unicorn?
          "#{GitHub.scheme}://orca-api-staging.service.azure-eastus.github.net/twirp"
        else
          @orca_base_url ||= ENV[ORCA_BASE_URL].to_s
        end
      end

      def orca_hmac_key=(key)
        @orca_hmac_key = key
      end

      def orca_hmac_key
        @orca_hmac_key ||= ENV[ORCA_HMAC_KEY].to_s
      end
    end
  end

  extend Config::Orca
end
