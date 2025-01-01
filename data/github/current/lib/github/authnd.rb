# typed: true
# frozen_string_literal: true

require "authnd-client"
require "scientist"

module GitHub
  module Authnd
    autoload :Experiment, "github/authnd/experiment"

    SERVICE_NAME = "authnd"

    RETRYABLE_ERRORS = [Faraday::Error, Faraday::TimeoutError, Net::OpenTimeout]
    MAX_ATTEMPTS = 3

    # Public: Gets the default authenticator for the provided catalog_service.
    # Each catalog_service has a default authenticator that is used when making authentication requests.
    # This authenticator is memoized, by catalog_service, so all requests made with it will share the same HTTP connection.
    def self.authenticator_for(catalog_service)
      raise ArgumentError, "catalog_service must be a string" unless catalog_service.is_a? String

      @authenticators ||= Hash.new do |hash, key|
        conn = faraday_conn(GitHub.authnd_service_url)

        # NOTE: The "default proc" for a hash does _not_ automatically add the returned value to the hash.
        # https://ruby-doc.org/core-3.0.1/Hash.html#class-Hash-label-Default+Proc
        hash[key] = create_authenticator(conn, catalog_service: key)
      end

      @authenticators[catalog_service]
    end

    # Public: Creates a new authenticator for the provided catalog_service, using the provided Faraday connection.
    # This method ignores the memoized authenticators, and creates a new one for the provided catalog_service.
    def self.create_authenticator(conn, catalog_service:)
      raise ArgumentError, "catalog_service must be a string" unless catalog_service.is_a? String

      # important - make sure to only apply retry middleware on functions we know are idempotent.
      ::Authnd::Client::Authenticator.new(conn, catalog_service: catalog_service) do |client|
        client.use :authenticate, with: [
          [::Authnd::Client::Middleware::Timing, { instrumenter: GitHub }],
          [::Authnd::Client::Middleware::Retry, { instrumenter: GitHub, max_attempts: MAX_ATTEMPTS, retryable_errors: RETRYABLE_ERRORS, retry_factor: true }],
        ]
      end
    end

    # Public: Gets the default credential manager for the provided catalog_service.
    # Each catalog_service has a default credential manager that is used when making credential management requests.
    # This credential manager is memoized, by catalog_service, so all requests made with it will share the same HTTP connection.
    def self.credential_manager_for(catalog_service)
      raise ArgumentError, "catalog_service must be a string" unless catalog_service.is_a? String

      @credential_managers ||= Hash.new do |hash, key|
        conn = faraday_conn(GitHub.authnd_service_url)

        # NOTE: The "default proc" for a hash does _not_ automatically add the returned value to the hash.
        # https://ruby-doc.org/core-3.0.1/Hash.html#class-Hash-label-Default+Proc
        hash[key] = create_credential_manager(conn, catalog_service: key)
      end

      @credential_managers[catalog_service]
    end

    # Public: Creates a new credential manager for the provided catalog_service, using the provided Faraday connection.
    # This method ignores the memoized credential managers, and creates a new one for the provided catalog_service.
    def self.create_credential_manager(conn, catalog_service:)
      raise ArgumentError, "catalog_service must be a string" unless catalog_service.is_a? String

      # important - make sure to only apply retry middleware on functions we know are idempotent.
      ::Authnd::Client::CredentialManager.new(conn, catalog_service: catalog_service) do |client|
        client.use :find_credentials, with: [
          [::Authnd::Client::Middleware::Timing, { instrumenter: GitHub }],
          [::Authnd::Client::Middleware::Retry, { instrumenter: GitHub, max_attempts: MAX_ATTEMPTS, retryable_errors: RETRYABLE_ERRORS }],
        ]
        client.use %i[
          issue_token
          revoke_credentials_by_id
          revoke_credentials
          verify_credentials
        ], with: [
          [::Authnd::Client::Middleware::Timing, { instrumenter: GitHub }],
        ]
      end
    end

    # Public: Gets the default mobile device manager for the provided catalog_service.
    # Each catalog_service has a default mobile device manager that is used when making mobile device requests.
    # This mobile device manager is memoized, by catalog_service, so all requests made with it will share the same HTTP connection.
    def self.mobile_device_manager_for(catalog_service)
      raise ArgumentError, "catalog_service must be a string" unless catalog_service.is_a? String

      @mobile_device_managers ||= Hash.new do |hash, key|
        conn = faraday_conn(GitHub.authnd_service_url, connection_timeout: 0.5, response_timeout: 0.5)

        # NOTE: The "default proc" for a hash does _not_ automatically add the returned value to the hash.
        # https://ruby-doc.org/core-3.0.1/Hash.html#class-Hash-label-Default+Proc
        hash[key] = create_mobile_device_manager(conn, catalog_service: key)
      end

      @mobile_device_managers[catalog_service]
    end

    # Public: Creates a new mobile device manager for the provided catalog_service, using the provided Faraday connection.
    # This method ignores the memoized mobile device managers, and creates a new one for the provided catalog_service.
    def self.create_mobile_device_manager(conn, catalog_service:)
      raise ArgumentError, "catalog_service must be a string" unless catalog_service.is_a? String

      # important - make sure to only apply retry middleware on functions we know are idempotent.
      # `request_device_auth` is the only function on the mobile device manager that is not idempotent.
      # `register_device_key` is considered idempotent because:
      #     - it revokes any existing keys for the supplied oauth access ID before registering the key
      #     - since it always revokes first, we don't run into unique constraint issues and therefore it's safe to be called with client retries
      # `approve_device_key` and `reject_device_auth` aren't necessarily idempotent, but can be called with client retries because:
      #     - they approve/reject the given auth request (if possible) and return success result
      #     - if the request is already approved/rejected, the API returns already approved/rejected result
      #     - the clients don't behave any differently with either type of result
      ::Authnd::Client::MobileDeviceManager.new(conn, catalog_service: catalog_service) do |client|
        client.use %i[
          find_device_auth_key_registration
          find_device_auth_key_registrations
          get_device_auth_status
          find_active_device_auth
          register_device_key
          revoke_device_auth_key_by_oauth_access_id
          revoke_device_keys_by_user_id
          revoke_device_keys_by_oauth_access_ids
          revoke_device_keys_by_ids
          reject_device_auth
          approve_device_auth
        ], with: [
          [::Authnd::Client::Middleware::Timing, { instrumenter: GitHub }],
          [::Authnd::Client::Middleware::Retry, { instrumenter: GitHub, max_attempts: MAX_ATTEMPTS, retryable_errors: RETRYABLE_ERRORS }],
        ]
        client.use :request_device_auth, with: [
          [::Authnd::Client::Middleware::Timing, { instrumenter: GitHub }],
        ]
      end
    end

    # Public: Is the authnd service available?
    # This returns false in all enterprise scenarios, because the authnd service is not currently part of GHES.
    def self.available?
      return false if GitHub.enterprise?
      true
    end

    # Public: Is the authnd experiment enabled?
    def self.experiments_enabled?
      return false unless available?
      return true if GitHub.flipper[:authnd_experiment].enabled?
    end

    # Disable raise on mismatch by default
    GitHub::Authnd::Experiment.raise_on_mismatches = false

    private_class_method def self.faraday_conn(url, connection_timeout: nil, response_timeout: nil)
      Faraday.new(url: "#{url}/twirp") do |conn|
        conn.use GitHub::FaradayMiddleware::RequestID
        conn.use GitHub::FaradayMiddleware::TenantContext
        conn.use GitHub::FaradayMiddleware::HMACAuth, hmac_key: GitHub.authnd_service_hmac_key
        conn.use GitHub::FaradayMiddleware::Datadog, stats: GitHub.dogstats, service_name: SERVICE_NAME, enable_path_tag: true
        conn.use GitHub::FaradayMiddleware::Staffbar, url: url
        conn.use GitHub::FaradayMiddleware::Resilient, name: SERVICE_NAME, options: {
          instrumenter: GitHub,
          sleep_window_seconds: 10,
          error_threshold_percentage: 25,
          window_size_in_seconds: 60,
          bucket_size_in_seconds: 10,
        }
        conn.options[:open_timeout] = connection_timeout ? connection_timeout : GitHub.authnd_service_connection_timeout
        conn.options[:timeout] = response_timeout ? response_timeout : GitHub.authnd_service_response_timeout
        conn.adapter :persistent_excon
      end
    end
  end
end
