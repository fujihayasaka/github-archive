# typed: true
# frozen_string_literal: true

require "authnd-client"
require "scientist"

module GitHub
  module Authnd
    autoload :Experiment, "github/authnd/experiment"

    SERVICE_NAME = "authnd"

    # Public: Gets the default authenticator for the provided catalog_service.
    # Each catalog_service has a default authenticator that is used when making authentication requests.
    # This authenticator is memoized, by catalog_service, so all requests made with it will share the same HTTP connection.
    def self.authenticator(catalog_service = calling_catalog_service)
      raise ArgumentError, "catalog_service must be provided" unless catalog_service.present?

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
      raise ArgumentError, "catalog_service must be provided" unless catalog_service.present?

      # important - make sure to only apply retry middleware on functions we know are idempotent.
      ::Authnd::Client::Authenticator.new(conn, catalog_service: catalog_service) do |client|
        client.use :authenticate, with: [
          [::Authnd::Client::Middleware::Timing, { instrumenter: GitHub }],
          [::Authnd::Client::Middleware::Retry, retry_middleware_settings],
        ]
      end
    end

    # Public: Gets the default credential manager for the provided catalog_service.
    # Each catalog_service has a default credential manager that is used when making credential management requests.
    # This credential manager is memoized, by catalog_service, so all requests made with it will share the same HTTP connection.
    def self.credential_manager(catalog_service = calling_catalog_service)
      raise ArgumentError, "catalog_service must be provided" unless catalog_service.present?

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
      raise ArgumentError, "catalog_service must be provided" unless catalog_service.present?

      retryable_operations = %i[
        find_credentials
        verify_credentials
      ]
      non_retryable_operations = %i[
        revoke_credentials_by_id
        revoke_credentials
      ]

      if GitHub.authnd_issue_token_retryable
        # though PATv2 issue token requests aren't purely idempotent (from the authnd side), they are from the Dotcom
        # side.  To avoid test flakes due to infrequent RPC failure (e.g. due to network flakes), we should retry
        # these RPCs in tests.
        retryable_operations << :issue_token
      else
        non_retryable_operations << :issue_token
      end

      # important - make sure to only apply retry middleware on functions we know are idempotent.
      ::Authnd::Client::CredentialManager.new(conn, catalog_service: catalog_service) do |client|
        client.use retryable_operations, with: [
          [::Authnd::Client::Middleware::Timing, { instrumenter: GitHub }],
          [::Authnd::Client::Middleware::Retry, retry_middleware_settings(retry_factor: false)],
        ]
        client.use non_retryable_operations, with: [
          [::Authnd::Client::Middleware::Timing, { instrumenter: GitHub }],
        ]
      end
    end

    # Public: Gets the default identity manager for the provided catalog_service.
    # Each catalog_service has a default identity manager that is used when making identity management requests.
    # This identity manager is memoized, by catalog_service, so all requests made with it will share the same HTTP connection.
    def self.identity_manager(catalog_service = calling_catalog_service)
      raise ArgumentError, "catalog_service must be provided" unless catalog_service.present?

      @identity_managers ||= Hash.new do |hash, key|
        conn = faraday_conn(GitHub.authnd_service_url)

        # NOTE: The "default proc" for a hash does _not_ automatically add the returned value to the hash.
        # https://ruby-doc.org/core-3.0.1/Hash.html#class-Hash-label-Default+Proc
        hash[key] = create_identity_manager(conn, catalog_service: key)
      end

      @identity_managers[catalog_service]
    end

    # Public: Creates a new identity manager for the provided catalog_service, using the provided Faraday connection.
    # This method ignores the memoized identity managers, and creates a new one for the provided catalog_service.
    def self.create_identity_manager(conn, catalog_service:)
      raise ArgumentError, "catalog_service must be provided" unless catalog_service.present?

      # important - make sure to only apply retry middleware on functions we know are idempotent.
      ::Authnd::Client::IdentityManager.new(conn, catalog_service: catalog_service) do |client|
        client.use %i[
          discovery_document
          jwks
        ], with: [
          [::Authnd::Client::Middleware::Timing, { instrumenter: GitHub }],
          [::Authnd::Client::Middleware::Retry, retry_middleware_settings],
        ]
      end
    end

    # Public: Gets the default token exchanger for the provided catalog_service.
    # Intended to only be used in tests.
    def self.stateless_token_exchanger(catalog_service = calling_catalog_service)
      raise ArgumentError, "catalog_service must be provided" unless catalog_service.present?

      @token_exchangers ||= Hash.new do |hash, key|
        conn = faraday_conn(GitHub.authnd_service_url)

        # NOTE: The "default proc" for a hash does _not_ automatically add the returned value to the hash.
        # https://ruby-doc.org/core-3.0.1/Hash.html#class-Hash-label-Default+Proc
        hash[key] = create_stateless_token_exchanger(conn, catalog_service: key)
      end

      @token_exchangers[catalog_service]
    end

    # Public: Creates a new token exchanger  for the provided catalog_service, using the provided Faraday connection.
    # This method ignores the memoized token exchanger, and creates a new one for the provided catalog_service.
    def self.create_stateless_token_exchanger(conn, catalog_service:)
      raise ArgumentError, "catalog_service must be provided" unless catalog_service.present?

      # important - make sure to only apply retry middleware on functions we know are idempotent.
      ::Authnd::Client::TokenExchanger.new(conn, catalog_service: catalog_service) do |client|
        client.use :exchange_token, with: [
          [::Authnd::Client::Middleware::Timing, { instrumenter: GitHub }],
          [::Authnd::Client::Middleware::Retry, retry_middleware_settings],
        ]
      end
    end

    # Public: Gets the default token verifier.
    def self.stateless_token_verifier
      @token_verifier ||= ::Authnd::Client::StatelessTokenVerifier.new(secret: GitHub.authnd_token_exchange_secret)
    end

    # Public: Gets the default mobile device manager for the provided catalog_service.
    # Each catalog_service has a default mobile device manager that is used when making mobile device requests.
    # This mobile device manager is memoized, by catalog_service, so all requests made with it will share the same HTTP connection.
    def self.mobile_device_manager(catalog_service = calling_catalog_service)
      raise ArgumentError, "catalog_service must be provided" unless catalog_service.present?

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
      raise ArgumentError, "catalog_service must be provided" unless catalog_service.present?

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
          [::Authnd::Client::Middleware::Retry, retry_middleware_settings(retry_factor: false)],
        ]
        client.use :request_device_auth, with: [
          [::Authnd::Client::Middleware::Timing, { instrumenter: GitHub }],
        ]
      end
    end

    # Resolve calling catalog service for memoizing the authnd clients
    def self.calling_catalog_service
      GitHub.context[:catalog_service].to_s.underscore.presence || "github/github"
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
      true if GitHub.flipper[:authnd_experiment].enabled?
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

    private_class_method def self.retry_middleware_settings(retry_factor: true)
      retryable_errors = [Faraday::Error, Faraday::TimeoutError, Net::OpenTimeout, Excon::Errors::Timeout]
      if GitHub.authnd_retry_proto_errors
        # server-side timeouts are reported as `internal: context cancelled` in these proto errors.  they should be
        # retryable client-side in tests.
        retryable_errors += [::Authnd::Proto::Error]
      end


      opts = {
        instrumenter: GitHub,
        max_attempts: GitHub.authnd_request_max_attempts,
        retryable_errors: retryable_errors,
        retry_factor: retry_factor,
      }
      opts[:wait_seconds] = GitHub.authnd_request_wait_seconds if GitHub.authnd_request_wait_seconds
      opts
    end
  end
end
