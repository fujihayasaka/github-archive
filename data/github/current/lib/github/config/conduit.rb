# typed: false
# frozen_string_literal: true

module GitHub
  module Config
    module Conduit
      def conduit_feed_enabled?
        return false if enterprise?

        GitHub.flipper.enabled?(:conduit_feed)
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
