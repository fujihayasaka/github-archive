# typed: true
# frozen_string_literal: true

module GitHub
  module Config
    module Kredz
      extend T::Helpers

      requires_ancestor { Kernel }

      # The address of the kredz service.
      #
      # e.g. "kredz.service.iad.github.net:1918"
      attr_reader :kredz_address

      def kredz_address=(val)
        @kredz = nil
        @kredz_address = val
      end

      # The HMAC signature secret for request verification.
      # This HMAC signature secret is specific to requests to Kredz.
      attr_reader :kredz_hmac_secret

      def kredz_hmac_secret=(val)
        @kredz = nil
        @kredz_hmac_secret = val
      end

      # A TWIRP client to communicate with the kredz client.
      #
      # Returns a TWIRP client for the kredz service, or returns nil if the address is not configured.
      def kredz
        @kredz ||= build_kredz_twirp_client(
          addr: kredz_address,
          hmac_secret: GitHub.kredz_hmac_secret,
        )
      end

      def build_kredz_twirp_client(addr:, hmac_secret:, timeout: 10)
        require "faraday"
        require "github-kredz"

        hmac_secrets = hmac_secret.split(",")
        connection = Faraday.new(url: addr) do |conn|
          conn.request(:retry, max: 2)
          conn.use GitHub::FaradayMiddleware::RequestID
          conn.use GitHub::FaradayMiddleware::HMACAuth, hmac_key: hmac_secrets[hmac_secrets.length - 1]
          conn.adapter Faraday.default_adapter
        end

        GitHub::Launch::Services::Credz::CredentialsServiceClient.new(connection)
      end
    end
  end

  extend Config::Kredz
end
