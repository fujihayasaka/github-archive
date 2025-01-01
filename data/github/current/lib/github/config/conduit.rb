# typed: false
# frozen_string_literal: true

module GitHub
  module Config
    module Conduit
      def conduit_enabled?(user: nil)
        return false if enterprise?

        # This feature flag check is to guard against the Feed showing on new Proxima Stamps still being
        # configured, for more informaton see:
        # https://github.com/github/conduit/blob/main/docs/development/adding_a_proxima_stamp.md
        FeatureFlag.vexi.enabled?(:conduit_enabled, user, default: true)
      end

      def conduit_twirp_url
        GitHub.environment.fetch("CONDUIT_URL", "http://localhost:8008/twirp")
      end

      def conduit_hmac_key
        GitHub.environment.fetch("CONDUIT_HMAC_KEY", "conduithmac")
      end

      def conduit_client
        @conduit_client ||= if Rails.env.test?
          ::Conduit::FakeClient.new
        else
          ::Conduit::Client.new
        end
      end
    end
  end

  extend Config::Conduit
end
