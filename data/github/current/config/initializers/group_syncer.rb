# typed: true
# frozen_string_literal: true

require "group_syncer"
require "twirp/hmac"
require "faraday_middleware/circuit_breaker"

module GroupSyncer
  SERVICE_NAME = "group-syncer"

  RETRYABLE_PATHS = [
    "/twirp/group_syncer.v1.Health/Ping",
    "/twirp/group_syncer.v1.Tenants/Register",
    "/twirp/group_syncer.v1.Groups/List",
    "/twirp/group_syncer.v1.TeamMappings/List",
    "/twirp/group_syncer.v1.TeamMappings/Update",
  ]

  RETRY_CHECK = proc do |env, _exception|
    RETRYABLE_PATHS.include?(env[:url].request_uri)
  end

  RETRY_CB = proc do |env, _options, retries, exception|
    tags = [
      "status:#{env[:status]}",
      "retries:#{retries}",
      "rpc:#{env[:url].request_uri.sub("/twirp/", "")}",
      "error:#{exception.class}",
    ]
    GitHub.dogstats.increment("group_syncer.client.retry", tags: tags)
  end

  def self.client
    # Initialize the original client if it's not already initialized
    if !defined?(@client) && !FeatureFlag.vexi.enabled_or_raise?(:group_syncer_hmac_rotation) # rubocop:disable GitHub/FeatureManagement/NoVexiEnabledOrRaiseUsage
      hmac_signing_service =
        if key = GitHub.group_syncer_service_hmac_secret_key.presence
          Twirp::HMAC::SigningService.new(key: key)
        end

      connection = build_connection(hmac_signing_service: hmac_signing_service)
      @client = GroupSyncer::Client.new(connection)
    end

    # Initialize the updated client if it's not already initialized
    if !defined?(@updated_client) && FeatureFlag.vexi.enabled_or_raise?(:group_syncer_hmac_rotation) # rubocop:disable GitHub/FeatureManagement/NoVexiEnabledOrRaiseUsage
      hmac_signing_service_updated =
        if key = GitHub.group_syncer_service_hmac_secret_primary_key.presence
          Twirp::HMAC::SigningService.new(key: key)
        end

      updated_connection = build_connection(hmac_signing_service: hmac_signing_service_updated)
      @updated_client = GroupSyncer::Client.new(updated_connection)
    end

    # Return the client based on the feature flag status
    FeatureFlag.vexi.enabled_or_raise?(:group_syncer_hmac_rotation) ? @updated_client : @client # rubocop:disable GitHub/FeatureManagement/NoVexiEnabledOrRaiseUsage
  end

  def self.client_with_timeout(timeout)
    hmac_signing_service = if FeatureFlag.vexi.enabled_or_raise?(:group_syncer_hmac_rotation) # rubocop:disable GitHub/FeatureManagement/NoVexiEnabledOrRaiseUsage
      if key = GitHub.group_syncer_service_hmac_secret_primary_key.presence
        Twirp::HMAC::SigningService.new(key: key)
      end
    else
      if key = GitHub.group_syncer_service_hmac_secret_key.presence
        Twirp::HMAC::SigningService.new(key: key)
      end
    end

    connection = build_connection(timeout: timeout, hmac_signing_service: hmac_signing_service)
    GroupSyncer::Client.new(connection)
  end

  def self.build_connection(uri: GitHub.group_syncer_service_uri, timeout: GitHub.group_syncer_service_timeout, hmac_signing_service: nil)
    GitHub::FaradayClient::Internal.new(url: uri) do |c|
      c.use Twirp::HMAC::RequestSigningMiddleware, hmac_signing_service if hmac_signing_service.present?
      c.use FaradayMiddleware::CircuitBreaker, { instrumenter: GitHub, circuit_name: SERVICE_NAME }
      c.request :retry, max: 2, retry_statuses: [503], retry_if: RETRY_CHECK, retry_block: RETRY_CB
      c.adapter(:typhoeus)
      c.options[:timeout] = timeout
      c.options[:open_timeout] = timeout
    end
  end
end
