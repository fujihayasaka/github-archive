# typed: true
# frozen_string_literal: true

# Code for Request-HMAC verification. The Request-HMAC header can be sent by
# internal services with API requests to identify themselves as trusted.
module Api::App::HmacDependency
  extend T::Helpers

  REQUEST_HMAC_HEADER = "HTTP_REQUEST_HMAC"
  REQUEST_HMAC_INVALID = "Request-HMAC is not valid."
  HMAC_ALGORITHM = "sha256"

  # Pattern for internal API hmac keys environment variable names (non-twirp)
  INTERNAL_HMAC_KEYS_PATTERN = /\AAPI_INTERNAL_(?<client_name>[A-Z_]+?)_HMAC_KEYS\Z/

  class InvalidRequestHMAC < StandardError; end
  class MissingRequestHMACKeys < StandardError; end

  # Is this a request from an internal service with a valid Request-HMAC header?
  #
  # Sets `env[:request_hmac_key]` with the value of the matching HMAC key if
  # it returns true.
  #
  # Returns Boolean.
  def hmac_authenticated_internal_service_request?
    received_hmac = env[REQUEST_HMAC_HEADER]
    return false unless received_hmac.present?
    hmac_status, matching_key = T.cast(self.class, T.class_of(Api::App)).verify_request_hmac(received_hmac)

    if hmac_status == :success
      env[:request_hmac_key] = matching_key
      env[:internal_client_id] = T.cast(self.class, T.class_of(Api::App)).api_internal_hmac_settings.fetch(matching_key, "unknown")
      true
    else
      false
    end
  end

  # While we transition internal APIs request HMACs are not required and are
  # only checked by default if a request HMAC is sent in the request. But, as
  # support for internal APIs are added, individual APIs can require the request
  # HMAC. Once all internal APIs have been migrated we can remove this
  # conditional and always require request HMACs.
  def require_request_hmac?
    false
  end

  module ClassMethods
    extend T::Helpers

    include Kernel

    # Takes the HMAC of an integer epoch timestamp with key.
    def request_hmac(time, key)
      GitHub::RequestHmacValidator.request_hmac(time, key)
    end

    # While we transition, use the same shared key as the content HMAC. Eventually
    # we will raise a NotImplementedError and require subclasses to define a key.
    def request_hmac_keys
      return @request_hmac_keys if defined?(@request_hmac_keys)
      # Rather than have to define this for every single subclass, we follow a
      # naming convention. Api::Internal::Pages results in a
      # config value of GitHub.api_internal_pages_hmac_key.
      config_value = "#{self.to_s.underscore.gsub("/", "_")}_hmac_keys"
      # During the transition we support either per-endpoint defined HMAC key(s)
      # OR the global key currently used for the content HMAC we are moving away
      # from.
      @request_hmac_keys =
        GitHub.try(config_value).presence || Array(GitHub.internal_api_hmac_key.to_s)
    end

    def verify_request_hmac(received_hmac)
      GitHub::RequestHmacValidator.verify_request_hmac(received_hmac, request_hmac_keys)
    end

    # The Internal API HMAC keys and their associated client names.
    #
    # Returns a Hash with the individual HMAC keys as String keys and associated client names as
    # String values.
    def api_internal_hmac_settings
      @api_internal_hmac_settings ||= api_internal_hmac_settings_from_env
    end

    # Harvest HMAC keys and associated client names from environment variables with a naming pattern.
    #
    # This harvests HMAC keys and client names from the pattern defined as INTERNAL_HMAC_KEYS_PATTERN.
    #
    # Examples
    # Given these environment variable settings:
    #
    #
    #     API_INTERNAL_FOO_HMAC_KEYS="foohmac"
    #     API_INTERNAL_BAR_HMAC_KEYS="barhmac"
    #     API_INTERNAL_BAZ_HMAC_KEYS="bazhmac"
    #
    # The result would be:
    #
    #     {
    #       "foohmac"  => "foo",
    #       "barhmac"  => "bar",
    #       "bazhmac"  => "baz",
    #     }
    #
    # Returns a Hash with the individual internal API HMAC keys as String keys and associated client names as
    # String values.
    def api_internal_hmac_settings_from_env(env = ENV)
      env.each_with_object({}) do |(env_key_name, value), settings|
        if (client_name = env_key_name[INTERNAL_HMAC_KEYS_PATTERN, :client_name])
          client_formatted = client_name.downcase.underscore
          value.split.each do |hmac_key|
            settings[hmac_key] = client_formatted
          end
        end
      end
    end
  end

  requires_ancestor { Api::App }
  mixes_in_class_methods(ClassMethods)
end
