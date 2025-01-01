# typed: true
# frozen_string_literal: true

require "secret_scanning_proto"

class GitHub::TokenScanning::Service::Client
  extend T::Sig
  include GitHub::Memoizer

  # Represents an error when calling to TSS
  class Error < StandardError
  end

  SERVICE_NAME = "token-scanning-service"
  FAILBOT_APP_NAME = "token-scanning-service"

  READ_TIMEOUT = GitHub.enterprise? ? 9.0 : 3.0 # seconds
  METRICS_READ_TIMEOUT = 9.0 # seconds
  CUSTOM_PATTERNS_EXTENDED_TIMEOUT = 6.0 # seconds
  EXPERIMENTAL_AI_AUTOFIX_AUDIT_TIMEOUT = 15.0 # seconds

  ERRORS_TO_RESCUE = T.let([
    Faraday::SSLError,
    Faraday::Error,
    Faraday::ConnectionFailed,
  ].freeze, T::Array[T.class_of(Faraday::Error)])

  # Pass in nil for the actor to short-circuit the actor-scope check and always hit the production deployment
  def initialize(actor)
    if actor.respond_to?(:flipper_id)
      @staging = T.let(GitHub.flipper[:token_scanning_use_staging].enabled?(actor) && GitHub.dynamic_lab?, T::Boolean)
    else
      @staging = false
    end
  end

  def self.staging_connection
    @staging_connection ||= new_conn(GitHub.token_scanning_staging_url)
  end

  def self.production_connection
    @production_connection ||= new_conn(GitHub.token_scanning_url)
  end

  def self.metrics_staging_connection
    @metrics_staging_connection ||= new_conn(GitHub.token_scanning_staging_url, timeout: METRICS_READ_TIMEOUT)
  end

  def self.metrics_production_connection
    @metrics_production_connection ||= new_conn(GitHub.token_scanning_url, timeout: METRICS_READ_TIMEOUT)
  end

  def self.custom_patterns_extended_timeout_staging_connection
    @extended_timeout_staging_connection ||= new_conn(GitHub.token_scanning_staging_url, timeout: CUSTOM_PATTERNS_EXTENDED_TIMEOUT)
  end

  def self.custom_patterns_extended_timeout_production_connection
    @extended_timeout_production_connection ||= new_conn(GitHub.token_scanning_url, timeout: CUSTOM_PATTERNS_EXTENDED_TIMEOUT)
  end

  def self.experimental_autofix_ai_extended_timeout_connection
    @extended_timeout_experimental_ai_connection ||= new_conn(GitHub.token_scanning_url, timeout: EXPERIMENTAL_AI_AUTOFIX_AUDIT_TIMEOUT)
  end

  def experimental_ai_connection
    self.class.experimental_autofix_ai_extended_timeout_connection
  end

  def self.production_scans_api_connection
    @prod_scans_api_connection ||= self.new_conn(GitHub.token_scanning_scans_api_url)
  end

  def connection
    @staging ? self.class.staging_connection : self.class.production_connection
  end

  def metrics_connection
    @staging ? self.class.metrics_staging_connection : self.class.metrics_production_connection
  end

  def custom_patterns_extended_timeout_connection
    @staging ? self.class.custom_patterns_extended_timeout_staging_connection : self.class.custom_patterns_extended_timeout_production_connection
  end

  def scans_api_connection
    @staging ? self.class.staging_connection : self.class.production_scans_api_connection
  end

  def self.send_message_to_failbot(msg)
    error = Error.new(msg)
    error.set_backtrace(caller)
    Failbot.report(error, { app: FAILBOT_APP_NAME })
  end

  def self.wrap_tokens(tokens, repository)
    tokens.map { |token| wrap_token(token, repository) }
  end

  # TODO add type to `data` param
  sig { params(token: GitHub::Proto::SecretScanning::Api::V2::Token, repository: Repository, data: T.untyped).returns(GitHub::TokenScanning::Service::Token) }
  def self.wrap_token(token, repository, data = nil)
    GitHub::TokenScanning::Service::Token.new(token, repository, data)
  end

  def self.wrap_token_location(location, repository)
    GitHub::TokenScanning::Service::TokenLocation.new(location, repository)
  end

  def self.to_resolution(resolution)
    resolution = resolution.to_s.to_sym.upcase
    resolved_resolution = GitHub::Proto::SecretScanning::Api::V2::Token::Resolution.resolve(resolution)
    if resolved_resolution != GitHub::Proto::SecretScanning::Api::V2::Token::Resolution::NO_RESOLUTION
      resolved_resolution
    end
  end

  sig { returns(GitHub::Proto::SecretScanning::Api::V2::Clients::TokenAPI) }
  memoize def v2_client
    GitHub::Proto::SecretScanning::Api::V2::Clients::TokenAPI.new(connection)
  end

  sig { returns(GitHub::Proto::SecretScanning::Api::V2::Clients::TokenAPI) }
  memoize def experimental_ai_client
    GitHub::Proto::SecretScanning::Api::V2::Clients::TokenAPI.new(experimental_ai_connection)
  end

  sig { returns(GitHub::Proto::SecretScanning::Api::V3::Clients::CustomPatternAPI) }
  memoize def custom_patterns_api_client_v3
    GitHub::Proto::SecretScanning::Api::V3::Clients::CustomPatternAPI.new(connection)
  end

  sig { returns(GitHub::Proto::SecretScanning::Api::V3::Clients::CustomPatternAPI) }
  memoize def custom_patterns_api_client_v3_with_extended_timeout
    GitHub::Proto::SecretScanning::Api::V3::Clients::CustomPatternAPI.new(custom_patterns_extended_timeout_connection)
  end

  sig { returns(GitHub::Proto::SecretScanning::Api::V2::Clients::CustomPatternAPI) }
  memoize def custom_patterns_api_client
    GitHub::Proto::SecretScanning::Api::V2::Clients::CustomPatternAPI.new(connection)
  end

  sig { returns(GitHub::Proto::SecretScanning::Api::V2::Clients::CustomPatternAPI) }
  memoize def custom_patterns_api_client_with_extended_timeout
    GitHub::Proto::SecretScanning::Api::V2::Clients::CustomPatternAPI.new(custom_patterns_extended_timeout_connection)
  end

  sig { returns(GitHub::Proto::SecretScanning::Api::V1::ScansAPI) }
  memoize def scans_api_client
    GitHub::Proto::SecretScanning::Api::V1::ScansAPI.new(connection)
  end

  sig { returns(GitHub::Proto::SecretScanning::Api::V2::Clients::ScansAPI) }
  memoize def scans_api_client_v2
    GitHub::Proto::SecretScanning::Api::V2::Clients::ScansAPI.new(scans_api_connection)
  end

  sig { returns(GitHub::Proto::SecretScanning::Api::V1::DryRunsAPI) }
  memoize def dry_runs_api_client
    GitHub::Proto::SecretScanning::Api::V1::DryRunsAPI.new(connection)
  end

  sig { returns(GitHub::Proto::SecretScanning::Api::V1::MetricsAPI) }
  memoize def metrics_api_client
    GitHub::Proto::SecretScanning::Api::V1::MetricsAPI.new(metrics_connection)
  end

  sig { returns(GitHub::Proto::SecretScanning::Api::V1::JobGroupsAPI) }
  memoize def job_groups_api_client
    GitHub::Proto::SecretScanning::Api::V1::JobGroupsAPI.new(connection)
  end

  def with_error_reporting
    rpc = T.must(T.must(caller_locations(1, 1))[0]).base_label
    tags = ["rpc:#{rpc}"]

    response = yield
    if response.nil?
      tags << "error:empty_response"
      GitHub.dogstats.increment("secret_scanning.service_error", tags: tags)
      self.class.send_message_to_failbot("Nil response from token-scanning-service")
    elsif response.error && response.error.code != :not_found
      self.class.send_message_to_failbot("Error response from token-scanning-service: #{response.error.msg}")
    end
    response
  rescue *ERRORS_TO_RESCUE, RuntimeError => e
    T.must(tags) << "error:#{e.class.name}"
    GitHub.dogstats.increment("secret_scanning.service_error", tags: tags)
    Failbot.report(e, { app: FAILBOT_APP_NAME })
    nil
  end

  def scan_push(options)
    with_error_reporting { scans_api_client_v2.scan_push(options) }
  end

  def scan_bytes(options)
    with_error_reporting { scans_api_client_v2.scan_bytes(options) }
  end

  sig do
    params(options: T.any(GitHub::Proto::SecretScanning::Scans::V2::AddBypassReviewerRequest, T::Hash[Symbol, T.untyped]))
      .returns(T.nilable(Twirp::ClientResp[GitHub::Proto::SecretScanning::Scans::V2::AddBypassReviewerResponse]))
  end
  def add_bypass_reviewer(options)
    with_error_reporting { scans_api_client_v2.add_bypass_reviewer(options) }
  end

  sig do
    params(options: T.any(GitHub::Proto::SecretScanning::Scans::V2::RemoveBypassReviewerRequest, T::Hash[Symbol, T.untyped]))
      .returns(T.nilable(Twirp::ClientResp[Google::Protobuf::Empty]))
  end
  def remove_bypass_reviewer(options)
    with_error_reporting { scans_api_client_v2.remove_bypass_reviewer(options) }
  end

  sig do
    params(options: T.any(GitHub::Proto::SecretScanning::Scans::V2::GetBypassReviewersRequest, T::Hash[Symbol, T.untyped]))
      .returns(T.nilable(Twirp::ClientResp[GitHub::Proto::SecretScanning::Scans::V2::GetBypassReviewersResponse]))
  end
  def get_bypass_reviewers(options)
    with_error_reporting { scans_api_client_v2.get_bypass_reviewers(options) }
  end

  def add_bypass(options)
    with_error_reporting { scans_api_client.add_bypass(options) }
  end

  def promote_bypass(options)
    with_error_reporting { scans_api_client.promote_bypass(options) }
  end

  def get_bypass_placeholder(options)
    with_error_reporting { scans_api_client.get_bypass_placeholder(options) }
  end

  def get_tokens(options)
    with_error_reporting { v2_client.get_tokens(options) }
  end

  def get_tokens_mean_time_to_remediation(options)
    with_error_reporting { v2_client.get_tokens_mean_time_to_remediation(options) }
  end

  sig do
    params(options: T.any(GitHub::Proto::SecretScanning::Api::V2::GetTokenRequest, T::Hash[Symbol, T.untyped]))
      .returns(T.nilable(Twirp::ClientResp[
        T.nilable(GitHub::Proto::SecretScanning::Api::V2::GetTokenResponse)
      ]))
  end
  def get_token(options)
    with_error_reporting { v2_client.get_token(options) }
  end

  sig do
    params(options: T.any(GitHub::Proto::SecretScanning::Api::V2::GetTokenLocationsRequest, T::Hash[Symbol, T.untyped]))
      .returns(T.nilable(Twirp::ClientResp[
        T.nilable(GitHub::Proto::SecretScanning::Api::V2::GetTokenLocationsResponse)
      ]))
  end
  def get_token_locations(options)
    with_error_reporting { v2_client.get_token_locations(options) }
  end

  def resolve_token(options)
    with_error_reporting { v2_client.resolve_token(options) }
  end

  def resolve_tokens(options)
    with_error_reporting { v2_client.resolve_tokens(options) }
  end

  sig do
    params(options: T.any(GitHub::Proto::SecretScanning::Api::V2::ReportTokenRequest, T::Hash[Symbol, T.untyped]))
      .returns(T.nilable(Twirp::ClientResp[
        T.nilable(GitHub::Proto::SecretScanning::Api::V2::ReportTokenResponse)
      ]))
  end
  def report_token(options)
    with_error_reporting { v2_client.report_token(options) }
  end

  def get_token_counts(options)
    with_error_reporting { v2_client.get_token_counts(options) }
  end

  def get_token_group_by_counts(options)
    with_error_reporting { v2_client.get_token_group_by_counts(options) }
  end

  def get_timeline(options)
    with_error_reporting { v2_client.get_timeline(options) }
  end

  sig do
    params(options: T.any(GitHub::Proto::SecretScanning::Api::V2::GetGeneratedAlertAutofixRequest, T::Hash[Symbol, T.untyped]))
      .returns(T.nilable(Twirp::ClientResp[
        T.nilable(GitHub::Proto::SecretScanning::Api::V2::GetGeneratedAlertAutofixResponse)
      ]))
  end
  def get_generated_alert_autofix(options)
    with_error_reporting { experimental_ai_client.get_generated_alert_autofix(options) }
  end


  sig do
    params(options: T.any(GitHub::Proto::SecretScanning::Api::V2::GetGeneratedAlertActivityAuditRequest, T::Hash[Symbol, T.untyped]))
      .returns(T.nilable(Twirp::ClientResp[
        T.nilable(GitHub::Proto::SecretScanning::Api::V2::GetGeneratedAlertActivityAuditResponse)
      ]))
  end
  def get_generated_alert_activity_audit(options)
    with_error_reporting { experimental_ai_client.get_generated_alert_activity_audit(options) }
  end

  def validate_enabled_repos(options)
    with_error_reporting { v2_client.validate_enabled_repos(options) }
  end

  def get_token_validation_status(options)
    with_error_reporting { v2_client.get_token_validation_status(options) }
  end

  def get_pattern_matches(options)
    # Allow for a longer timeout to support patterns with multiple and complex post processing expressions
    with_error_reporting { custom_patterns_api_client_with_extended_timeout.get_pattern_matches(options) }
  end

  sig do
    params(options: T.any(GitHub::Proto::SecretScanning::Api::V3::GetCustomPatternsRequest, T::Hash[Symbol, T.untyped]))
      .returns(T.nilable(Twirp::ClientResp[GitHub::Proto::SecretScanning::Api::V3::GetCustomPatternsResponse]))
  end
  def get_custom_patterns_paginated(options)
    with_error_reporting { custom_patterns_api_client_v3.get_custom_patterns(options) }
  end

  def get_custom_patterns_total_count(options)
    with_error_reporting { custom_patterns_api_client_v3.get_custom_patterns_count(options) }
  end

  def get_custom_pattern(options)
    with_error_reporting { custom_patterns_api_client.get_custom_pattern(options) }
  end

  def create_custom_pattern(options)
    with_error_reporting { custom_patterns_api_client.create_custom_pattern(options) }
  end

  def publish_custom_pattern(options)
    with_error_reporting { custom_patterns_api_client.publish_custom_pattern(options) }
  end

  def update_custom_pattern(options)
    with_error_reporting { custom_patterns_api_client.update_custom_pattern(options) }
  end

  def update_custom_pattern_settings(options)
    with_error_reporting { custom_patterns_api_client_v3.update_custom_pattern_settings(options) }
  end

  def delete_custom_pattern(options)
    with_error_reporting { custom_patterns_api_client.delete_custom_pattern(options) }
  end

  def delete_custom_patterns(options)
    with_error_reporting { custom_patterns_api_client_v3.delete_custom_patterns(options) }
  end

  def get_generated_expressions(options)
    # CAPI requests need a longer timeout due to the natural latency of AI-based endpoints.
    with_error_reporting { custom_patterns_api_client_v3_with_extended_timeout.get_generated_expressions(options) }
  end

  def cancel_dry_runs_for_custom_pattern(options)
    with_error_reporting { dry_runs_api_client.cancel_dry_runs_for_custom_pattern(options) }
  end

  def dry_run_metadata_for_pattern(options)
    with_error_reporting { dry_runs_api_client.dry_run_metadata_for_pattern(options) }
  end

  def dry_run_results_for_pattern(options)
    with_error_reporting { dry_runs_api_client.dry_run_results_for_pattern(options) }
  end

  def get_alerts_for_insights_backfill(options)
    with_error_reporting { metrics_api_client.get_alerts_for_insights_backfill(options) }
  end

  def get_token_alert_metrics(options)
    with_error_reporting { metrics_api_client.get_token_alert_metrics(options) }
  end

  def get_token_push_protection_metrics(options)
    with_error_reporting { metrics_api_client.get_token_push_protection_metrics(options) }
  end

  def get_push_protection_metrics(options)
    with_error_reporting { metrics_api_client.get_push_protection_metrics(options) }
  end

  def get_push_protection_metrics_for_repos(options)
    with_error_reporting { metrics_api_client.get_push_protection_metrics_for_repos(options) }
  end

  def get_block_counts_by_token_type(options)
    with_error_reporting { metrics_api_client.get_block_counts_by_token_type(options) }
  end

  def get_block_counts_by_repo(options)
    with_error_reporting { metrics_api_client.get_block_counts_by_repo(options) }
  end

  def get_bypass_counts_by_token_type(options)
    with_error_reporting { metrics_api_client.get_bypass_counts_by_token_type(options) }
  end

  def get_bypass_counts_by_repo(options)
    with_error_reporting { metrics_api_client.get_bypass_counts_by_repo(options) }
  end

  def get_job_group_summary(options)
    with_error_reporting { job_groups_api_client.get_job_group_summary(options) }
  end

  def self.new_conn(service_url, timeout: READ_TIMEOUT)
    Faraday.new(url: service_url) do |conn|
      conn.use GitHub::FaradayMiddleware::RequestID
      conn.use GitHub::FaradayMiddleware::TenantContext
      conn.use GitHub::FaradayMiddleware::HMACAuth, hmac_key: GitHub.token_scanning_hmac_key
      conn.use GitHub::FaradayMiddleware::Datadog, stats: GitHub.dogstats, service_name: SERVICE_NAME
      conn.use GitHub::FaradayMiddleware::Staffbar, url: service_url
      conn.use GitHub::FaradayMiddleware::Resilient, name: SERVICE_NAME, options: {
        instrumenter: GitHub,
        sleep_window_seconds: 10,
        error_threshold_percentage: 5,
        window_size_in_seconds: 30,
        bucket_size_in_seconds: 5,
      }
      conn.request :retry,
        max: 2,
        methods: [:post], # in twirp, everything is post
        retry_statuses: (500...600).to_a
      conn.options[:open_timeout] = 0.1 # connection open timeout in seconds.
      conn.options[:timeout] = timeout
      conn.adapter :persistent_excon
    end
  end
end
