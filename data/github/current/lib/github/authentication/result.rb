# typed: true
# frozen_string_literal: true

# Object describing the result of a login attempt. #success returns true if
# the authentication was successful. If successful, #user returns a User or
# Bot object. If unsuccessful, #user may return the user who was attempting to
# authenticate, but it may also be nil.
class GitHub::Authentication::Result
  attr_reader  :success, :user, :failure_type, :message, :two_factor_type, :authnd_response, :token_format
  attr_accessor :has_compromised_password, :authenticated_device,
    :sign_in_verification_method
  attr_writer :failure_reason

  def initialize(data = {})
    data.each do |k, v|
      ivar = "@#{k}".to_sym
      instance_variable_set ivar, v
    end
  end

  # Mostly for stats purpose, a blank reason isn't very useful
  def failure_reason
    @failure_reason || failure_type
  end

  def self.success(user, data = {})
    new data.merge success: true, user: user
  end

  def self.failure(data = {})
    new data.merge success: false
  end

  def self.at_auth_limit_failure(data = {})
    failure data.merge(failure_type: :auth_limit)
  end

  def self.at_device_auth_limit_failure(data = {})
    failure data.merge(failure_type: :device_auth_limit)
  end

  def self.password_failure(data = {})
    failure data.merge(failure_type: :password)
  end

  def self.token_failure(data = {})
    failure data.merge(failure_type: :token)
  end

  def self.suspended_failure(data = {})
    failure data.merge(failure_type: :suspended)
  end

  def self.suspended_oauth_application_failure(data = {})
    failure data.merge(failure_type: :oauth_application_suspended)
  end

  def self.suspended_integration_failure(data = {})
    failure data.merge(failure_type: :integration_suspended)
  end

  def self.suspended_installation_failure(data = {})
    failure data.merge(failure_type: :installation_suspended)
  end

  def self.attribution_only_system_identity_failure(data = {})
    failure data.merge(failure_type: :attribution_only_system_identity)
  end

  def self.two_factor_failure(failed_user, two_factor_type, data = {})
    failure data.merge(
      failure_type: :two_factor,
      user: failed_user,
      two_factor_type: two_factor_type,
    )
  end

  def self.allow_integrations_failure(data = {})
    failure data.merge(failure_type: :allow_integrations)
  end

  def self.allow_user_via_granular_actor_failure(data = {})
    failure data.merge(failure_type: :allow_user_via_granular_actor)
  end

  def self.external_response_ignored(data = {})
    failure data.merge(failure_type: :external_response_ignored)
  end

  def self.unverified_device_failure(data = {})
    failure data.merge(failure_type: :unverified_device)
  end

  def self.weak_password_failure(data = {})
    failure data.merge(failure_type: :weak_password)
  end

  def self.web_api_with_password_failure(data = {})
    failure data.merge(failure_type: :web_api_with_password)
  end

  def self.api_with_password_failure(data = {})
    failure data.merge(failure_type: :api_with_password)
  end

  def self.application_owned_by_spammy_failure(data = {})
    failure data.merge(failure_type: :application_owned_by_spammy)
  end

  def success?
    success
  end

  def failure?
    !success?
  end

  def password_failure?
    failure? && failure_type == :password
  end

  def new_token_format?
    token_format == "new"
  end

  def ldap_timeout?
    failure? && failure_reason == :ldap_timeout
  end

  def two_factor_partial_sign_in?
    failure? && failure_type == :two_factor
  end

  def allow_integrations_failure?
    failure? && failure_type == :allow_integrations
  end

  def allow_user_via_granular_actor_failure?
    failure? && failure_type == :allow_user_via_granular_actor
  end

  def token_failure?
    failure? && failure_type == :token
  end

  def suspended_failure?
    failure? && failure_type == :suspended
  end

  def suspended_oauth_application_failure?
    failure? && failure_type == :oauth_application_suspended
  end

  def suspended_integration_failure?
    failure? && failure_type == :integration_suspended
  end

  def suspended_installation_failure?
    failure? && failure_type == :installation_suspended
  end

  def attribution_only_system_identity_failure?
    failure? && failure_type == :attribution_only_system_identity
  end

  def at_auth_limit_failure?
    failure? && failure_type == :auth_limit
  end

  def at_device_auth_limit_failure?
    failure? && failure_type == :device_auth_limit
  end

  def external_response_ignored?
    failure? && failure_type == :external_response_ignored
  end

  def unverified_device_failure?
    failure? && failure_type == :unverified_device
  end

  def weak_password_failure?
    failure? && failure_type == :weak_password
  end

  def web_api_with_password_failure?
    failure? && failure_type == :web_api_with_password
  end

  def api_with_password_failure?
    failure? && failure_type == :api_with_password
  end

  def application_owned_by_spammy_failure?
    failure? && failure_type == :application_owned_by_spammy
  end

  # Public: was a correct password supplied as part of this auth attempt?
  # two_factor_partial_sign_in events indicate an otp is required but the
  # password was correct.
  def correct_password?
    success? || two_factor_partial_sign_in?
  end
end
