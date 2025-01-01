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

  DENY = Authzd::Response.from_decision(Authzd::Proto::Decision.deny)
  ALLOW = Authzd::Response.from_decision(Authzd::Proto::Decision.allow)

  DEFAULT_ENUMERATION_TIMEOUT = 5.0
  DEFAULT_CONDITIONAL_ACCESS_TIMEOUT = 5.0

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
  DEFAULT_AUTHZD_PORT = Rails.env.test? ? "8081" : "8091"
  DEFAULT_AUTHZD_ENDPOINT = "http://localhost:#{DEFAULT_AUTHZD_PORT}/twirp"
  RETRYABLE_ERRORS = [Faraday::Error, Faraday::TimeoutError, Faraday::ConnectionFailed, Net::OpenTimeout]
  SERVICE_NAME = "authzd".freeze

  CIRCUIT_BREAKER_ERROR_THRESHOLD     = 25
  CIRCUIT_BREAKER_CUSTOM_SLEEP_WINDOW = 10

  def self.client
    if mesh_enabled? && GitHub.flipper[:use_authzd_mesh_client].enabled?
      @mesh_faraday_conn ||= faraday_conn(mesh_endpoint)
      @mesh_client ||= create_client(@mesh_faraday_conn)
    else
      @faraday_conn ||= faraday_conn(endpoint)
      @client ||= create_client(@faraday_conn)
    end
  end

  def self.enumerator_client
    if mesh_enabled? && GitHub.flipper[:use_authzd_mesh_enumerator_client].enabled?
      @mesh_enumerator_faraday_conn ||= enumerator_faraday_conn(mesh_endpoint)
      @mesh_enumerator_client ||= create_enumerator_client(@mesh_enumerator_faraday_conn)
    else
      @enumerator_faraday_conn ||= enumerator_faraday_conn(endpoint)
      @enumerator_client ||= create_enumerator_client(@enumerator_faraday_conn)
    end
  end

  def self.conditional_access_client
    if !proxima?
      if GitHub.flipper[:use_authzd_persistent_excon_conditional_access_client].enabled?
        @noci_excon_conditional_access_faraday_conn ||= conditional_access_faraday_conn(noci_endpoint, :persistent_excon)
        @noci_excon_conditional_access_client ||= create_conditional_access_client(@noci_excon_conditional_access_faraday_conn)
      else
        @noci_conditional_access_faraday_conn ||= conditional_access_faraday_conn(noci_endpoint, :typhoeus)
        @noci_conditional_access_client ||= create_conditional_access_client(@noci_conditional_access_faraday_conn)
      end
    else
      control_endpoint_cap_client
    end
  end

  def self.mesh_conditional_access_client
    if mesh_enabled?
      if GitHub.flipper[:use_authzd_persistent_excon_conditional_access_client].enabled?
        @mesh_excon_conditional_access_faraday_conn ||= conditional_access_faraday_conn(mesh_endpoint, :persistent_excon)
        @mesh_excon_conditional_access_client ||= create_conditional_access_client(@mesh_excon_conditional_access_faraday_conn)
      else
        @mesh_conditional_access_faraday_conn ||= conditional_access_faraday_conn(mesh_endpoint, :typhoeus)
        @mesh_conditional_access_client ||= create_conditional_access_client(@mesh_conditional_access_faraday_conn)
      end
    else
      control_endpoint_cap_client
    end
  end

  def self.control_endpoint_cap_client
    if GitHub.flipper[:use_authzd_persistent_excon_conditional_access_client].enabled?
      @excon_conditional_access_faraday_conn ||= conditional_access_faraday_conn(endpoint, :persistent_excon)
      @excon_conditional_access_client ||= create_conditional_access_client(@excon_conditional_access_faraday_conn)
    else
      @conditional_access_faraday_conn ||= conditional_access_faraday_conn(endpoint, :typhoeus)
      @conditional_access_client ||= create_conditional_access_client(@conditional_access_faraday_conn)
    end
  end

  def self.controlaccess_client
    if mesh_enabled? && GitHub.flipper[:use_authzd_mesh_controlaccess_client].enabled?
      @mesh_controlaccess_faraday_conn ||= controlaccess_faraday_conn(mesh_endpoint)
      @mesh_controlaccess_client ||= create_controlaccess_client(@mesh_controlaccess_faraday_conn)
    else
      @controlaccess_faraday_conn ||= controlaccess_faraday_conn(endpoint)
      @controlaccess_client ||= create_controlaccess_client(@controlaccess_faraday_conn)
    end
  end

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
      f.options[:timeout] = authzd_enumeration_timeout
      f.options[:open_timeout] = authzd_enumeration_timeout
    end
  end

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
      middleware << Authzd::Middleware::CircuitBreaker.new(instrumenter: GitHub, circuit_name: circuit_name,
        sleep_window_seconds: CIRCUIT_BREAKER_CUSTOM_SLEEP_WINDOW,
        error_threshold_percentage: CIRCUIT_BREAKER_ERROR_THRESHOLD)
    end
    middleware << Authzd::Middleware::Retry.new(instrumenter: GitHub, max_attempts: 3, retryable_errors: RETRYABLE_ERRORS, retry_factor: true)
  end

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
      middleware << Authzd::Middleware::CircuitBreaker.new(instrumenter: GitHub, circuit_name: circuit_name,
        sleep_window_seconds: CIRCUIT_BREAKER_CUSTOM_SLEEP_WINDOW,
        error_threshold_percentage: CIRCUIT_BREAKER_ERROR_THRESHOLD)
    end
    middleware
  end

  def self.create_conditional_access_client(conn)
    Authzd::CapEvaluator::Client.new(conn) do |client|
      client.use :evaluate_policies_for_single_resource, with: build_cap_middleware("evaluate_policies_for_single_resource")
      client.use :evaluate_policies_for_filtering, with: build_cap_middleware("evaluate_policies_for_filtering")
    end
  end

  def self.build_cap_middleware(circuit_name)
    middleware = T.let([AuthzdTraceMiddleware.new("#{circuit_name}.first"), Authzd::Middleware::Timing.new(instrumenter: GitHub)], T::Array[Authzd::Middleware::Base])
    if use_circuit_breaker?
      middleware << Authzd::Middleware::CircuitBreaker.new(instrumenter: GitHub, circuit_name: circuit_name,
        sleep_window_seconds: CIRCUIT_BREAKER_CUSTOM_SLEEP_WINDOW,
        error_threshold_percentage: CIRCUIT_BREAKER_ERROR_THRESHOLD)
    end
    if circuit_name == "evaluate_policies_for_single_resource"
      # CAPTODO - enable retries for filtering as well
      middleware << Authzd::Middleware::CAPRetry.new(instrumenter: GitHub, max_attempts: 3, retryable_errors: RETRYABLE_ERRORS, retry_factor: true)
    end
    middleware << AuthzdTraceMiddleware.new("#{circuit_name}.last")
    middleware
  end

  def self.create_controlaccess_client(conn)
    Authzd::ControlAccess::Client.new(conn) do |client|
      client.use :check, with: [
        Authzd::Middleware::Timing.new(instrumenter: GitHub),
      ]
    end
  end

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

  # This is a helper method that determines if a user has a given role assigned.
  # It can be then used in science experiment ignore blocks to skip mismatches.
  #
  # Roles like "triage" and "maintain" are already in production, and they are based on top of
  # fine grained permissions (FGP). If a new FGP is added to a role, this would necessarily cause
  # a mismatch in callsites validated through science experiments, because the new role would behave
  # differently that the control and that would be intended.
  def self.user_has_role?(user, target, role)
    # check role being grained directly
    has_role = UserRole.find_by(actor_id: user, actor_type: "User", target_id: target.id, target_type: target.class.name, role: role).present?

    # check role being granted indirectly
    if !has_role && target.owner.organization?
      org_teams = Team.where(id: user.teams(with_ancestors: true), organization: target.owner).pluck(:id)
      has_role |= UserRole.find_by(actor_id: org_teams, actor_type: "Team", target_id: target.id, target_type: target.class.name, role: role).present?
    end

    has_role
  end

  def self.endpoint=(endpoint)
    @endpoint = endpoint
    @client = nil
    @conditional_access_client = nil
    @excon_conditional_access_client = nil
    @enumerator_client = nil
    @controlaccess_client = nil
  end

  def self.endpoint
    @endpoint ||= if Rails.env.production?
      GitHub.environment.fetch("AUTHZD_ENDPOINT") { |missing_var| raise "#{missing_var} cannot be found in the environment" }
    else
      GitHub.environment.fetch("AUTHZD_ENDPOINT", DEFAULT_AUTHZD_ENDPOINT)
    end
  end

  def self.mesh_endpoint=(mesh_endpoint)
    @mesh_endpoint = mesh_endpoint
    @mesh_client = nil
    @mesh_conditional_access_client = nil
    @mesh_excon_conditional_access_client = nil
    @mesh_enumerator_client = nil
    @mesh_controlaccess_client = nil
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

  def self.noci_endpoint=(noci_endpoint)
    @noci_endpoint = noci_endpoint
    @noci_conditional_access_client = nil
    @noci_excon_conditional_access_client = nil
  end

  def self.noci_endpoint
    # AUTHZD_NO_CUSTOM_INGRESS_ENDPOINT routes to a k8s service via glb with _no_ custom ingress between glb and authzd.
    # This should be more performant than AUTHZD_ENDPOINT which is glb + custom ingress, and currently AUTHZD_MESH_ENDPOINT too
    # This endpoint will be used while latency issues are resolved on the mesh.
    @noci_endpoint ||= if Rails.env.production?
      GitHub.environment.fetch("AUTHZD_NO_CUSTOM_INGRESS_ENDPOINT") { |missing_var| raise "#{missing_var} cannot be found in the environment" }
    else
      GitHub.environment.fetch("AUTHZD_ENDPOINT", DEFAULT_AUTHZD_ENDPOINT)
    end
  end

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
