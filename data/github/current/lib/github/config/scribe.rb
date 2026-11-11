# typed: true
# frozen_string_literal: true

module GitHub
  module Config
    module Scribe
      def scribe_enabled?(user: nil)
        FeatureFlag.vexi.enabled?(:scribe_enabled, user, default: false)
      end

      def scribe_twirp_url
        GitHub.environment.fetch("SCRIBE_URL", "http://localhost:28080/twirp")
      end

      def scribe_hmac_key
        GitHub.environment.fetch("SCRIBE_HMAC_KEY", "scribehmac")
      end

      def scribe_client
        @scribe_client ||= ::Scribe::Client.new
      end
    end
  end

  extend Config::Scribe
end
