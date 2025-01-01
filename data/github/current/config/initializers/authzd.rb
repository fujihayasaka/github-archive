# typed: true
# frozen_string_literal: true

require "authzd-client"

module Authzd
  NotApplicableError = Class.new(StandardError)

  DENY = Authzd::Response.from_decision(Authzd::Proto::Decision.deny)
  ALLOW = Authzd::Response.from_decision(Authzd::Proto::Decision.allow)

  DEFAULT_ENUMERATION_TIMEOUT = 5.0

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

  # use different port in dev and test to allow running two servers at the same time
  DEFAULT_AUTHZD_PORT = Rails.env.test? ? "8081" : "8091"
  DEFAULT_AUTHZD_ENDPOINT = "http://localhost:#{DEFAULT_AUTHZD_PORT}/twirp"
  RETRYABLE_ERRORS = [Faraday::Error, Faraday::TimeoutError, Faraday::ConnectionFailed, Net::OpenTimeout]
  SERVICE_NAME = "authzd".freeze

  CIRCUIT_BREAKER_ERROR_THRESHOLD     = 25
  CIRCUIT_BREAKER_CUSTOM_SLEEP_WINDOW = 10

  def self.client
    @faraday_conn ||= faraday_conn(endpoint)
    @client ||= create_client(@faraday_conn)
  end

  def self.enumerator_client
    @enumerator_faraday_conn ||= enumerator_faraday_conn(endpoint)
    @enumerator_client ||= create_enumerator_client(@enumerator_faraday_conn)
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

  def self.create_client(conn)
    Authzd::Authorizer::Client.new(conn) do |client|
      client.use :authorize, with: [
        Authzd::Middleware::Timing.new(instrumenter: GitHub),
        Authzd::Middleware::ResponseWrapper.new(instrumenter: GitHub),
        Authzd::Middleware::CircuitBreaker.new(instrumenter: GitHub, circuit_name: "authorize",
                                               sleep_window_seconds: CIRCUIT_BREAKER_CUSTOM_SLEEP_WINDOW,
                                               error_threshold_percentage: CIRCUIT_BREAKER_ERROR_THRESHOLD),
        Authzd::Middleware::Retry.new(instrumenter: GitHub, max_attempts: 3, retryable_errors: RETRYABLE_ERRORS, retry_factor: true),
      ]
      client.use :batch_authorize, with: [
        Authzd::Middleware::Timing.new(instrumenter: GitHub),
        Authzd::Middleware::ResponseWrapper.new(instrumenter: GitHub),
        Authzd::Middleware::CircuitBreaker.new(instrumenter: GitHub, circuit_name: "batch_authorize",
                                               sleep_window_seconds: CIRCUIT_BREAKER_CUSTOM_SLEEP_WINDOW,
                                               error_threshold_percentage: CIRCUIT_BREAKER_ERROR_THRESHOLD),
        Authzd::Middleware::Retry.new(instrumenter: GitHub, max_attempts: 3, retryable_errors: RETRYABLE_ERRORS, retry_factor: true),
      ]
    end
  end

  def self.create_enumerator_client(conn)
    Authzd::Enumerator::Client.new(conn) do |client|
      client.use :for_actor, with: [
        Authzd::Middleware::Timing.new(instrumenter: GitHub),
        Authzd::Middleware::CircuitBreaker.new(instrumenter: GitHub, circuit_name: "for_actor",
                                               sleep_window_seconds: CIRCUIT_BREAKER_CUSTOM_SLEEP_WINDOW,
                                               error_threshold_percentage: CIRCUIT_BREAKER_ERROR_THRESHOLD),
      ]

      client.use :for_subject, with: [
        Authzd::Middleware::Timing.new(instrumenter: GitHub),
        Authzd::Middleware::CircuitBreaker.new(instrumenter: GitHub, circuit_name: "for_subject",
                                               sleep_window_seconds: CIRCUIT_BREAKER_CUSTOM_SLEEP_WINDOW,
                                               error_threshold_percentage: CIRCUIT_BREAKER_ERROR_THRESHOLD),
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
    @client_with_factor = nil
  end

  def self.endpoint
    @endpoint ||= if Rails.env.production?
      GitHub.environment.fetch("AUTHZD_ENDPOINT") { |missing_var| raise "#{missing_var} cannot be found in the environment" }
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
