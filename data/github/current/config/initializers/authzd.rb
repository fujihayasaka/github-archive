# typed: true
# frozen_string_literal: true

require "authzd-client"

class AuthzdTraceMiddleware < Authzd::Middleware::Base
  def initialize(name)
    @name = name
  end

  def perform(req, metadata = {})
    GitHub.tracer.in_span("AuthzdTraceMiddleware.perform.#{@name}", kind: :internal) do
      request.perform(req, metadata)
    end
  end
end

module Authzd::ControlAccess
  class Request
    def rpc_name
      "check"
    end
  end
end

module Authzd
  NotApplicableError = Class.new(StandardError)

  DENY  = Authzd::Response.from_decision(Authzd::Proto::Decision.deny)
  ALLOW = Authzd::Response.from_decision(Authzd::Proto::Decision.allow)

  DEFAULT_ENUMERATION_TIMEOUT        = 5.0
  DEFAULT_CONDITIONAL_ACCESS_TIMEOUT = 7.0
  DEFAULT_CONTROLACCESS_TIMEOUT      = 8.0

  # Require AUTHZD_TIMEOUT from the environment in dotcom
  def self.authzd_timeout
    return 2.0 if !Rails.env.production? || GitHub.single_or_multi_tenant_enterprise?

    begin
      value = GitHub.environment.fetch("AUTHZD_TIMEOUT")
    rescue KeyError
      raise ArgumentError, "AUTHZD_TIMEOUT, has to be defined in the environment as a Float > 0.0 denoting seconds"
    end

    unless value.to_f > 0.0
      raise ArgumentError, "AUTHZD_TIMEOUT, expected to be a Float > 0.0 denoting seconds, but it's #{value}"
    end

    value.to_f
  end

  # Require AUTHZD_ENUMERATION_TIMEOUT from the environment in dotcom
  def self.authzd_enumeration_timeout
    return DEFAULT_ENUMERATION_TIMEOUT if !Rails.env.production? || GitHub.single_or_multi_tenant_enterprise?

    begin
      value = GitHub.environment.fetch("AUTHZD_ENUMERATION_TIMEOUT")
    rescue KeyError
      raise ArgumentError, "AUTHZD_ENUMERATION_TIMEOUT, has to be defined in the environment as a Float > 0.0 denoting seconds"
    end

    unless value.to_f > 0.0
      raise ArgumentError, "AUTHZD_ENUMERATION_TIMEOUT, expected to be a Float > 0.0 denoting seconds, but it's #{value}"
    end

    value.to_f
  end

  def self.authzd_conditional_access_timeout
    DEFAULT_CONDITIONAL_ACCESS_TIMEOUT
  end

  def self.authzd_controlaccess_timeout
    DEFAULT_CONTROLACCESS_TIMEOUT
  end

  def self.use_circuit_breaker?
    # do not use circuit breaker in tests
    # open circuits caused by one test can affect subsequent tests
    !Rails.env.test?
  end

  def self.mesh_enabled?
    GitHub.environment.fetch("SERVICE_MESH_ENABLED", "false") == "true"
  end

  def self.proxima?
    !!GitHub::Config::Proxima.current_stamp
  end

  # use different port in dev and test to allow running two servers at the same time
  DEFAULT_AUTHZD_PORT     = Rails.env.test? ? "8081" : "8091"
  DEFAULT_AUTHZD_ENDPOINT = "http://localhost:#{DEFAULT_AUTHZD_PORT}/twirp"

  RETRYABLE_ERRORS = [
    Faraday::Error,
    Faraday::TimeoutError,
    Faraday::ConnectionFailed,
    Net::OpenTimeout,
  ]

  SERVICE_NAME = "authzd".freeze

  CIRCUIT_BREAKER_ERROR_THRESHOLD     = 25
  CIRCUIT_BREAKER_CUSTOM_SLEEP_WINDOW = 10

  # ---------------------------------------------------------------------------
  # Authorizer client
  # ---------------------------------------------------------------------------
  def self.client
    if mesh_enabled? && FeatureFlag.vexi.enabled_or_raise?(:use_authzd_mesh_client) # rubocop:disable GitHub/FeatureManagement/NoVexiEnabledOrRaiseUsage
      @mesh_faraday_conn ||= faraday_conn(mesh_endpoint)
      @mesh_client ||= create_client(@mesh_faraday_conn)
    else
      @faraday_conn ||= faraday_conn(endpoint)
      @client ||= create_client(@faraday_conn)
    end
  end

  # ---------------------------------------------------------------------------
  # Enumerator client
  # ---------------------------------------------------------------------------
  def self.enumerator_client
    if mesh_enabled? && FeatureFlag.vexi.enabled_or_raise?(:use_authzd_mesh_enumerator_client) # rubocop:disable GitHub/FeatureManagement/NoVexiEnabledOrRaiseUsage
      @mesh_enumerator_faraday_conn ||= enumerator_faraday_conn(mesh_endpoint)
      @mesh_enumerator_client ||= create_enumerator_client(@mesh_enumerator_faraday_conn)
    else
      @enumerator_faraday_conn ||= enumerator_faraday_conn(endpoint)
      @enumerator_client ||= create_enumerator_client(@enumerator_faraday_conn)
    end
  end

  # ---------------------------------------------------------------------------
  # CAP (Conditional Access) client
  #
  # Both single_resource and filtering operations use CAPRetry middleware.
  # ---------------------------------------------------------------------------
  def self.conditional_access_client
    @cap_faraday_conn ||= conditional_access_faraday_conn(conditional_access_endpoint, :persistent_excon)
    @cap_client ||= create_conditional_access_client(@cap_faraday_conn)
  end

  # ---------------------------------------------------------------------------
  # ControlAccess client
  # ---------------------------------------------------------------------------
  def self.controlaccess_client
    @controlaccess_faraday_conn ||= controlaccess_faraday_conn(controlaccess_endpoint)
    @controlaccess_client ||= create_controlaccess_client(@controlaccess_faraday_conn)
  end

  # ---------------------------------------------------------------------------
  # Faraday connection builders
  # ---------------------------------------------------------------------------
  def self.faraday_conn(url)
    Faraday.new(url: url) do |f|
      f.use ::GitHub::FaradayMiddleware::RequestID
      f.adapter(:typhoeus)
      f.headers[:user_agent] = "github-#{GitHub.role}"
      f.options[:timeout] = authzd_timeout
      f.options[:open_timeout] = authzd_timeout
    end
  end

  def self.enumerator_faraday_conn(url)
    Faraday.new(url: url) do |f|
      f.use ::GitHub::FaradayMiddleware::RequestID
      f.use GitHub::FaradayMiddleware::HMACAuth, hmac_key: GitHub.authzd_api_hmac_key, header: "Request-HMAC"
      f.adapter(:typhoeus)
      f.headers[:user_agent] = "github-#{GitHub.role}"
      f.options[:timeout] = authzd_enumeration_timeout
      f.options[:open_timeout] = authzd_enumeration_timeout
    end
  end

  def self.conditional_access_faraday_conn(url, adapter)
    Faraday.new(url: url) do |f|
      f.use ::GitHub::FaradayMiddleware::RequestID
      f.use GitHub::FaradayMiddleware::HMACAuth, hmac_key: GitHub.authzd_api_hmac_key, header: "Request-HMAC"
      f.adapter(adapter)
      f.headers[:user_agent] = "github-#{GitHub.role}"
      f.options[:timeout] = authzd_conditional_access_timeout
      f.options[:open_timeout] = authzd_conditional_access_timeout
    end
  end

  def self.controlaccess_faraday_conn(url)
    Faraday.new(url: url) do |f|
      f.use ::GitHub::FaradayMiddleware::RequestID
      f.use GitHub::FaradayMiddleware::HMACAuth, hmac_key: GitHub.authzd_api_hmac_key, header: "Request-HMAC"
      f.adapter(:persistent_excon)
      f.headers[:user_agent] = "github-#{GitHub.role}"
      f.options[:timeout] = authzd_controlaccess_timeout
      f.options[:open_timeout] = authzd_controlaccess_timeout
    end
  end

  # ---------------------------------------------------------------------------
  # Authorizer client builder + middleware
  # ---------------------------------------------------------------------------
  def self.create_client(conn)
    Authzd::Authorizer::Client.new(conn) do |client|
      client.use :authorize, with: build_enforcer_middleware("authorize")
      client.use :batch_authorize, with: build_enforcer_middleware("batch_authorize")
    end
  end

  def self.build_enforcer_middleware(circuit_name)
    middleware = T.let([
      Authzd::Middleware::Timing.new(instrumenter: GitHub),
      Authzd::Middleware::ResponseWrapper.new(instrumenter: GitHub),
    ], T::Array[Authzd::Middleware::Base])

    if use_circuit_breaker?
      middleware << Authzd::Middleware::CircuitBreaker.new(
        instrumenter: GitHub,
        circuit_name: circuit_name,
        sleep_window_seconds: CIRCUIT_BREAKER_CUSTOM_SLEEP_WINDOW,
        error_threshold_percentage: CIRCUIT_BREAKER_ERROR_THRESHOLD
      )
    end

    middleware << Authzd::Middleware::Retry.new(
      instrumenter: GitHub,
      max_attempts: 3,
      retryable_errors: RETRYABLE_ERRORS,
      retry_factor: true
    )

    middleware
  end

  # ---------------------------------------------------------------------------
  # Enumerator client builder + middleware
  # ---------------------------------------------------------------------------
  def self.create_enumerator_client(conn)
    Authzd::Enumerator::Client.new(conn) do |client|
      client.use :for_actor, with: build_enumerator_middleware("for_actor")
      client.use :for_subject, with: build_enumerator_middleware("for_subject")
    end
  end

  def self.build_enumerator_middleware(circuit_name)
    middleware = T.let([
      Authzd::Middleware::Timing.new(instrumenter: GitHub),
    ], T::Array[Authzd::Middleware::Base])

    if use_circuit_breaker?
      middleware << Authzd::Middleware::CircuitBreaker.new(
        instrumenter: GitHub,
        circuit_name: circuit_name,
        sleep_window_seconds: CIRCUIT_BREAKER_CUSTOM_SLEEP_WINDOW,
        error_threshold_percentage: CIRCUIT_BREAKER_ERROR_THRESHOLD
      )
    end

    middleware
  end

  # ---------------------------------------------------------------------------
  # CAP client builder + middleware
  # ---------------------------------------------------------------------------

  # Both single_resource and filtering operations use CAPRetry middleware.
  def self.create_conditional_access_client(conn)
    Authzd::CapEvaluator::Client.new(conn) do |client|
      client.use :evaluate_policies_for_single_resource,
        with: build_cap_middleware("evaluate_policies_for_single_resource", retry_filtering: true)
      client.use :evaluate_policies_for_filtering,
        with: build_cap_middleware("evaluate_policies_for_filtering", retry_filtering: true)
    end
  end

  # Shared CAP middleware builder.
  #
  # - Always adds:
  #     * AuthzdTraceMiddleware (first + last)
  #     * Timing
  #     * CircuitBreaker (when enabled)
  #
  # - Adds CAPRetry for:
  #     * evaluate_policies_for_single_resource ALWAYS
  #     * evaluate_policies_for_filtering ONLY when retry_filtering: true
  #
  def self.build_cap_middleware(circuit_name, retry_filtering:)
    middleware = T.let([
      AuthzdTraceMiddleware.new("#{circuit_name}.first"),
      Authzd::Middleware::Timing.new(instrumenter: GitHub),
    ], T::Array[Authzd::Middleware::Base])

    if use_circuit_breaker?
      middleware << Authzd::Middleware::CircuitBreaker.new(
        instrumenter: GitHub,
        circuit_name: circuit_name,
        sleep_window_seconds: CIRCUIT_BREAKER_CUSTOM_SLEEP_WINDOW,
        error_threshold_percentage: CIRCUIT_BREAKER_ERROR_THRESHOLD
      )
    end

    should_add_retry =
      case circuit_name
      when "evaluate_policies_for_single_resource"
        true
      when "evaluate_policies_for_filtering"
        retry_filtering
      else
        false
      end

    if should_add_retry
      middleware << Authzd::Middleware::CAPRetry.new(
        instrumenter: GitHub,
        max_attempts: 3,
        retryable_errors: RETRYABLE_ERRORS,
        retry_factor: true
      )
    end

    middleware << AuthzdTraceMiddleware.new("#{circuit_name}.last")
    middleware
  end

  # ---------------------------------------------------------------------------
  # ControlAccess client builder + middleware
  # ---------------------------------------------------------------------------
  def self.create_controlaccess_client(conn)
    Authzd::ControlAccess::Client.new(conn) do |client|
      client.use :check, with: build_controlaccess_middleware("check")
    end
  end

  def self.build_controlaccess_middleware(circuit_name)
    middleware = T.let([
      AuthzdTraceMiddleware.new("#{circuit_name}.first"),
      Authzd::Middleware::Timing.new(instrumenter: GitHub),
    ], T::Array[Authzd::Middleware::Base])

    if use_circuit_breaker?
      middleware << Authzd::Middleware::CircuitBreaker.new(
        instrumenter: GitHub,
        circuit_name: circuit_name,
        sleep_window_seconds: CIRCUIT_BREAKER_CUSTOM_SLEEP_WINDOW,
        error_threshold_percentage: CIRCUIT_BREAKER_ERROR_THRESHOLD
      )
    end

    middleware << Authzd::Middleware::ControlAccessRetry.new(
      instrumenter: GitHub,
      max_attempts: 3,
      retryable_errors: RETRYABLE_ERRORS,
      retry_factor: true
    )

    middleware << AuthzdTraceMiddleware.new("#{circuit_name}.last")
    middleware
  end

  # ---------------------------------------------------------------------------
  # Science ignore helper
  # ---------------------------------------------------------------------------
  def self.ignore_error_in_science?(result)
    return false if !Rails.env.production?

    ignore = false

    if result.is_a? Authzd::Proto::Decision
      # FIXME batch requests should have their Authzd::Proto::Decision turned into Authzd::Proto::Response
      ## to include the exception and avoid having to check strings like this
      ignore = result.reason.include?("context deadline exceeded") ||
        result.reason.include?("request timed out") ||
        result.reason.include?("too many connection resets") ||
        result.reason.include?("execution expired") ||
        result.reason.include?("no connections are checked out") ||
        result.reason.include?("invalid connection") ||
        result.reason.include?("CircuitOpenError")
    elsif result.error != nil
      ignore = case result.error
      when Faraday::ConnectionFailed, Faraday::TimeoutError, Authzd::Middleware::CircuitBreaker::CircuitOpenError
        true
      else
        # ignore timeouts in the server side
        result.error.to_s.include?("context deadline exceeded") ||
          result.error.to_s.include?("request timed out") ||
          result.error.to_s.include?("too many connection resets") ||
          result.error.to_s.include?("execution expired") ||
          result.error.to_s.include?("no connections are checked out") ||
          result.error.to_s.include?("invalid connection") ||
          result.error.to_s.include?("CircuitOpenError")
      end
    end

    ignore
  end

  # ---------------------------------------------------------------------------
  # Role helper
  # ---------------------------------------------------------------------------
  # This is a helper method that determines if a user has a given role assigned.
  # It can be then used in science experiment ignore blocks to skip mismatches.
  #
  # Roles like "triage" and "maintain" are already in production, and they are based on top of
  # fine grained permissions (FGP). If a new FGP is added to a role, this would necessarily cause
  # a mismatch in callsites validated through science experiments, because the new role would behave
  # differently that the control and that would be intended.
  def self.user_has_role?(user, target, role)
    # check role being granted directly
    has_role = UserRole.find_by(
      actor_id: user,
      actor_type: "User",
      target_id: target.id,
      target_type: target.class.name,
      role: role
    ).present?

    # check role being granted indirectly
    if !has_role && target.owner.organization?
      org_teams = Team.where(id: user.teams(with_ancestors: true), organization: target.owner).pluck(:id)
      has_role |= UserRole.find_by(
        actor_id: org_teams,
        actor_type: "Team",
        target_id: target.id,
        target_type: target.class.name,
        role: role
      ).present?
    end

    has_role
  end

  # ---------------------------------------------------------------------------
  # Endpoint setters / getters (and cache reset)
  # ---------------------------------------------------------------------------
  def self.endpoint=(endpoint)
    @endpoint = endpoint

    #
    # Authorizer (non-mesh + mesh)
    #
    @client            = nil
    @faraday_conn      = nil
    @mesh_client       = nil
    @mesh_faraday_conn = nil

    #
    # Enumerator (non-mesh + mesh)
    #
    @enumerator_client            = nil
    @enumerator_faraday_conn      = nil
    @mesh_enumerator_client       = nil
    @mesh_enumerator_faraday_conn = nil

    #
    # Conditional access (CAP)
    #
    @cap_client       = nil
    @cap_faraday_conn = nil
  end

  def self.endpoint
    @endpoint ||= if Rails.env.production?
      GitHub.environment.fetch("AUTHZD_ENDPOINT") { |missing_var| raise "#{missing_var} cannot be found in the environment" }
    else
      GitHub.environment.fetch("AUTHZD_ENDPOINT", DEFAULT_AUTHZD_ENDPOINT)
    end
  end

  def self.controlaccess_endpoint=(controlaccess_endpoint)
    @controlaccess_endpoint     = controlaccess_endpoint
    @controlaccess_client       = nil
    @controlaccess_faraday_conn = nil
  end

  def self.controlaccess_endpoint
    @controlaccess_endpoint ||= if Rails.env.production?
      GitHub.environment.fetch("AUTHZD_CONTROLACCESS_ENDPOINT", endpoint)
    else
      GitHub.environment.fetch("AUTHZD_CONTROLACCESS_ENDPOINT", DEFAULT_AUTHZD_ENDPOINT)
    end
  end

  def self.conditional_access_endpoint=(conditional_access_endpoint)
    @conditional_access_endpoint = conditional_access_endpoint
    @cap_client                  = nil
    @cap_faraday_conn            = nil
  end

  def self.conditional_access_endpoint
    @conditional_access_endpoint ||= if Rails.env.production?
      GitHub.environment.fetch("AUTHZD_CONDITIONAL_ACCESS_ENDPOINT", endpoint)
    else
      GitHub.environment.fetch("AUTHZD_CONDITIONAL_ACCESS_ENDPOINT", DEFAULT_AUTHZD_ENDPOINT)
    end
  end

  def self.mesh_endpoint=(mesh_endpoint)
    @mesh_endpoint = mesh_endpoint

    #
    # Authorizer (mesh)
    #
    @mesh_client       = nil
    @mesh_faraday_conn = nil

    #
    # Enumerator (mesh)
    #
    @mesh_enumerator_client       = nil
    @mesh_enumerator_faraday_conn = nil

    #
    # ControlAccess (mesh – future-proof, even though we don't yet have a
    # mesh-specific Faraday conn here)
    #
    @mesh_controlaccess_client            = nil
    @mesh_excon_conditional_access_client = nil

    #
    # CAP
    #
    @cap_client       = nil
    @cap_faraday_conn = nil
  end

  def self.mesh_endpoint
    # AUTHZD_MESH_ENDPOINT will only be used during the cutover from glb to service mesh
    # Once cutover is complete in all environments, we will update AUTHZD_ENDPOINT to the same value as AUTHZD_MESH_ENDPOINT
    # We will then ramp down the feature flags, and ensure all traffic is still mesh-based.
    # Finally, we will remove the mesh-specific methods and variables used for rollout.
    @mesh_endpoint ||= if Rails.env.production?
      GitHub.environment.fetch("AUTHZD_MESH_ENDPOINT") { |missing_var| raise "#{missing_var} cannot be found in the environment" }
    else
      GitHub.environment.fetch("AUTHZD_ENDPOINT", DEFAULT_AUTHZD_ENDPOINT)
    end
  end

  # ---------------------------------------------------------------------------
  # Proto::Request extensions
  # ---------------------------------------------------------------------------
  class Proto::Request
    def action
      self["action"]
    end

    def actor_id
      self["actor.id"]
    end

    def actor_type
      self["actor.type"]
    end

    def subject_id
      self["subject.id"]
    end

    def subject_type
      self["subject.type"]
    end

    def [](key)
      attributes.detect { |attr| attr.id == key }&.value&.unwrap
    end

    def context
      Hash[
        attributes.map do |attr|
          [attr.id, attr.value&.unwrap]
        end
      ]
    end
  end
end
