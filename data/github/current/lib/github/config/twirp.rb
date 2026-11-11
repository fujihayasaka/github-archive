# typed: false
# frozen_string_literal: true

module GitHub
  module Config
    module Twirp

      # Pattern of environment variable names that are
      HMAC_KEYS_PATTERN = /\AAPI_INTERNAL_TWIRP_HMAC_KEYS_FOR_(?<client_name>[A-Z_]+?)\Z/

      # Public: Whether the internal Twirp API is enabled.
      #
      # Twirp is disabled by default.
      #
      # Returns a boolean.
      def twirp_enabled
        return @twirp_enabled if defined?(@twirp_enabled)
        @twirp_enabled = false
      end
      alias twirp_enabled? twirp_enabled
      attr_writer :twirp_enabled

      # Public: Whether the internal Twirp API supports special clients
      #         ("allowed", "disallowed") for more convenient testing of
      #         handler authorization.
      #
      # Disabled by default; for use in testing only.
      #
      # Returns a boolean.
      def twirp_supports_test_clients
        return @twirp_supports_test_clients if defined?(@twirp_supports_test_clients)
        @twirp_supports_test_clients = false
      end
      alias twirp_supports_test_clients? twirp_supports_test_clients
      attr_writer :twirp_supports_test_clients

      # Public: Add an HMAC key that will be associated with a given client name.
      #
      # client_name - a String identifying the client name (lowercase, underscored).
      # hmac_key - a String HMAC key, a single key.
      #
      # This information is harvested from environment variables in production and
      # from values provided manually (using #api_internal_twirp_add_client_hmac_key) in
      # development and test.
      #
      # Returns a Hash with the individual HMAC keys as String keys and associated client names as
      # String values.
      def api_internal_twirp_add_client_hmac_key(client_name, hmac_key)
        if GitHub::AppEnvironment.production?
          raise NotImplementedError, "Cannot manually set internal Twirp API keys in production. Use API_INTERNAL_TWIRP_HMAC_KEYS_FOR_[CLIENT_NAME] environment variables."
        end
        if (existing_client_name = api_internal_twirp_hmac_settings[hmac_key])
          raise ArgumentError, %Q(Duplicate internal Twirp API HMAC key for client "#{client_name}"; already used by "#{existing_client_name}")
        end
        api_internal_twirp_hmac_settings[hmac_key] = client_name
      end

      # Public: The HMAC keys configured for the internal Twirp API, used
      # for verifying HMAC-signed requests and identifying clients.
      #
      # Returns an Array of String values.
      def api_internal_twirp_hmac_keys
        api_internal_twirp_hmac_settings.keys
      end

      # The HMAC keys used for verifying HMAC-signed requests and their associated client
      # names.
      #
      # This information is harvested from environment variables in production and
      # from values provided manually (using #api_internal_twirp_add_client_hmac_key) in
      # development and test.
      #
      # Returns a Hash with the individual HMAC keys as String keys and associated client names as
      # String values.
      def api_internal_twirp_hmac_settings
        @api_internal_twirp_hmac_settings ||= api_internal_twirp_hmac_settings_from_env
      end

      # Harvest HMAC keys and associated client names from environment variables with a naming pattern.
      #
      # This harvests HMAC keys and client names from the pattern defined as HMAC_KEYS_PATTERN.
      #
      # Examples
      #
      # Given these environment variable settings:
      #
      #     API_INTERNAL_TWIRP_HMAC_KEYS_FOR_A_CLIENT="foohmac"
      #     API_INTERNAL_TWIRP_HMAC_KEYS_FOR_ANOTHER="barhmac bazhmac"
      #     API_INTERNAL_TWIRP_HMAC_KEYS_FOR_THIRD="quuxhmac"
      #
      # The result would be:
      #
      #     {
      #       "foohmac"  => "a_client",
      #       "barhmac"  => "another",
      #       "bazhmac"  => "another",
      #       "quuxhmac" => "third"
      #     }
      #
      # Returns a Hash with the individual HMAC keys as String keys and associated client names as
      # String values.
      def api_internal_twirp_hmac_settings_from_env(env = ENV)
        env.each_with_object({}) do |(env_name, value), acc|
          if (client_name = env_name[HMAC_KEYS_PATTERN, :client_name])
            underscored = client_name.downcase.underscore
            value.split.each do |hmac_key|
              acc[hmac_key] = underscored
            end
          end
        end
      end
    end
  end

  extend Config::Twirp
end
