# typed: true
# frozen_string_literal: true

module GitHub
  module Config
    module Varz
      extend T::Helpers

      requires_ancestor { Kernel }

      # The address of the varz service.
      #
      # e.g. "varz.service.iad.github.net:1918"
      attr_reader :varz_address

      def varz_address=(val)
        @varz = nil
        @varz_address = val
      end

      # The HMAC signature secret for request verification.
      # This HMAC signature secret is specific to requests to Varz.
      attr_reader :varz_hmac_secret

      def varz_hmac_secret=(val)
        @varz = nil
        @varz_hmac_secret = val
      end

      # A TWIRP client to communicate with the varz client.
      #
      # Returns a TWIRP client for the varz service, or returns nil if the address is not configured.
      def varz
        @varz ||= build_varz_twirp_client(
          addr: varz_address,
          hmac_secret: GitHub.varz_hmac_secret,
        )
      end

      def build_varz_twirp_client(addr:, hmac_secret:, timeout: 10)
        require "faraday"
        require "github-kredz"

        hmac_secrets = hmac_secret.split(",")
        connection = Faraday.new(url: addr) do |conn|
          conn.request(:retry, max: 2)
          conn.use GitHub::FaradayMiddleware::RequestID
          conn.use GitHub::FaradayMiddleware::HMACAuth, hmac_key: hmac_secrets[hmac_secrets.length - 1]
          conn.adapter Faraday.default_adapter
        end

        client = GitHub::Kredz::Services::Varz::VariablesServiceClient.new(connection)
        client
      end
    end
  end

  extend Config::Varz
end
