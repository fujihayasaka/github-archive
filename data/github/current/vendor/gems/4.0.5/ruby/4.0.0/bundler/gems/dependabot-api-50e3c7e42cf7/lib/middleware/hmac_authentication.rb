# frozen_string_literal: true

module Middleware
  class HmacAuthentication
    HMAC_ALGORITHM = "sha256"

    class TokenValidator
      REQUEST_HMAC_HEADER = "HTTP_REQUEST_HMAC"
      # Machines in the same network can have a clock skew
      # that prevents them from ever authenticating correctly
      # to the API server, even with a valid HMAC key on the client.
      #
      # This setting allows us to have a generous 10 minute
      # window within which the clocks can skew between the client & API server.
      REQUEST_HMAC_CLOCK_SKEW = 10.minutes

      def initialize
        @hmac_keys = Prius.get(:dependabot_api_hmac_keys).to_s.split(" ")
      end

      def permitted?(rack_env:)
        received_token = rack_env[REQUEST_HMAC_HEADER]
        client = rack_env["CLIENT"] || "unknown"

        # If there's no HMAC header in the request.
        return false if received_token.blank?

        # The HMAC is of the format <timestamp>.<sha256>
        # e.g. 1534188429.e7e00d966524ce8a5088109fa81ab9
        timestamp, hmac = received_token.split(".", 2)
        return false if timestamp.blank? || hmac.blank?

        # We only need the integer value going forward.
        timestamp = timestamp.to_i

        return false unless valid_timestamp?(timestamp)

        @hmac_keys.each_with_index do |key, index|
          expected_hmac = HmacAuthentication.request_hmac(
            key: key,
            time: Time.zone.at(timestamp)
          )

          # If any of the signatures match, we don't need to validate any more.
          next unless Rack::Utils.secure_compare(received_token, expected_hmac)

          Rails.logger.info "Request from '#{client}' client authenticated "\
                            "with secret '#{index}'"

          return true
        end

        false
      end

      private

      def valid_timestamp?(timestamp)
        # Allow for a bit of clock skew, latency, etc in either direction.
        timestamp > REQUEST_HMAC_CLOCK_SKEW.ago.to_i &&
          timestamp < REQUEST_HMAC_CLOCK_SKEW.from_now.to_i
      end
    end

    # Takes the HMAC of an integer epoch timestamp with key.
    def self.request_hmac(key:, time:)
      timestamp = time.to_i.to_s

      hmac = OpenSSL::HMAC.hexdigest(HMAC_ALGORITHM, key, timestamp)
      "#{timestamp}.#{hmac}"
    end

    def initialize(app, skip_paths: [])
      @app = app
      # Multiple simultaneous keys are supported to allow easy key rotation.
      # The keys are space delimited.
      @hmac_keys = Prius.get(:dependabot_api_hmac_keys).to_s.split(" ")
      # These paths are allowed to skip request hmac validation.
      @skip_paths = skip_paths
    end

    def call(env)
      path = env["PATH_INFO"]

      if skip_path?(path) || valid_hmac_token?(env)
        @app.call(env)
      else
        [401, {}, []]
      end
    end

    private

    def valid_hmac_token?(env)
      TokenValidator.new.permitted?(rack_env: env)
    end

    # Determines whether given path is allowed to skip request hmac validation.
    def skip_path?(path)
      @skip_paths.any? do |skip_path|
        skip_path.is_a?(Regexp) ? skip_path.match?(path) : skip_path == path
      end
    end
  end
end
