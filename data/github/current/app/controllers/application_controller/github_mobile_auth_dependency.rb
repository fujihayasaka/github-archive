# typed: true
# frozen_string_literal: true

# GitHub Mobile controller concern
# Helper methods for handling GitHub Mobile authentication requests
#
# For methods for managing the GitHub Mobile configuration: models/user/two_factor_authentication_dependency.rb
#
# See Also:
#   UserSession model: models/user_session.rb
#
module ApplicationController::GitHubMobileAuthDependency
  extend ActiveSupport::Concern
  extend T::Helpers

  include GitHubMobileAuthHelper

  requires_ancestor { ApplicationController }

  included do
    T.bind(self, AbstractController::Helpers::ClassMethods)
    helper_method :can_use_gh_mobile_auth?
    helper_method :has_recent_gh_mobile_and_2fa?
    helper_method :set_from_gh_mobile_session
    helper_method :initiate_mobile_auth_request
    helper_method :get_mobile_auth_request_status
  end

  MOBILE_AUTH_TYPES = {
    two_factor_login: "2fa_login",
    device_verification: "device_verification",
    two_factor_password_reset: "2fa_password_reset",
    sudo: "2fa_sudo_challenge"
  }

  GITHUB_MOBILE_AUTH_UNEXPECTED_ERROR_FLASH = "GitHub Mobile cannot be used for authentication at this time. Use a different verification method or try again later."

  def can_use_gh_mobile_auth?(user)
    user_and_session_can_use_gh_mobile_auth?(user)
  end

  # Is github mobile 2fa available as an auth factor for the environment, session, and current user?
  #
  # Returns boolean.
  def has_recent_gh_mobile_and_2fa?(user, since: 6.months.ago)
    user.has_mobile_app_activity?(since) && user.gh_mobile_auth_enabled?
  end

  # evaluate if the user is logging in from the gh mobile app
  def set_from_gh_mobile_session
    if Apps::Privileged.capable?(:mobile_web_session, app: @application)
      session[:is_gh_mobile_app] = true
    end
  end

  # Calls authnd to initiate a mobile auth request.
  #
  # Returns boolean indicating success.
  def initiate_mobile_auth_request(type, user, skip_challenge, suppress_flash)
    # delete active auth request session values if they are expired
    delete_gh_mobile_auth_session_values_if_expired!(type)

    # if there is an active auth request for this session, short circuit and show the mobile prompt immediately
    active_auth_request_id = session[:gh_mobile_request_id]
    active_auth_request_challenge = session[:gh_mobile_challenge]
    return true if active_auth_request_id.present?

    req_type = MOBILE_AUTH_TYPES[type]
    # if there isn't an active mobile auth request in progress for this session call authnd to generate a new one

    headers = {}
    enabled_features = [] # enabled FF features that authnd would like to use for rollouts
    if GitHub.flipper[:notifyd_rich_mobile_push].enabled?(user)
      enabled_features.push("notifyd_rich_mobile_push")
    end

    # enabled feature header should only be set if there are any enabled features that authnd wants
    # otherwise, we should not set the header at all
    if enabled_features.any?
      headers[Authnd::Client::ENABLED_FEATURES_HEADER] = Authnd::Client.format_enabled_features_for_header(enabled_features)
    end

    begin
      response = mobile_device_manager.request_device_auth(user.id, skip_challenge: skip_challenge, type: req_type, headers: headers)
    rescue ::Authnd::Proto::Error, Faraday::Error => err
      # report the error to Sentry
      Failbot.report!(err)
      GitHub.dogstats.increment("mobile_2fa.request_device_auth_failure",
        tags: ["reason:client_raised", "type:#{req_type}", "suppressed:#{suppress_flash}"])

      # if authnd fails unexpectedly, redirect to the fallback and explain unavailability
      anonymous_flash[:error] = GITHUB_MOBILE_AUTH_UNEXPECTED_ERROR_FLASH unless suppress_flash
      return false
    end

    unless response.result == :RESULT_SUCCESS
      GitHub.dogstats.increment("mobile_2fa.request_device_auth_failure",
        tags: ["reason:#{response.result}", "type:#{req_type}", "suppressed:#{suppress_flash}"])

      # if the user tried to access this page directly, and doesn't have a valid device key registered, redirect them to
      # the default two factor page and let them know what's up -- if they've stumbled onto this page, this is a small nudge to prompt them to download GitHub Mobile app
      if response.result == :RESULT_FAILED_NO_VALID_DEVICE_KEYS
        anonymous_flash[:error] = "It looks like you aren't signed into the GitHub mobile app. Sign in to GitHub Mobile and try again." unless suppress_flash
        return false
      end

      # if authnd reports an unknown error result, redirect to the OTP 2fa prompt and let them know there was an error with GitHub Mobile two-factor authentication
      anonymous_flash[:error] = GITHUB_MOBILE_AUTH_UNEXPECTED_ERROR_FLASH unless suppress_flash
      return false
    end

    # sanity check to ensure the response from authnd has an ID and expiration
    if response.nil? || response.id.nil? || response.id == 0 || response.expires_at_time.nil?
      anonymous_flash[:error] = GITHUB_MOBILE_AUTH_UNEXPECTED_ERROR_FLASH unless suppress_flash
      return false
    end

    # if authnd succeeded, store the response details in the session so they can be referenced
    # by the poller and on page refresh of the same session
    set_gh_mobile_auth_session_values(response.id, response.challenge, response.expires_at_time)
    true
  end

  # Calls authnd to get the status of an active auth request.
  #
  # Returns result status.
  def get_mobile_auth_request_status(type, user)
    return :STATUS_NOT_FOUND unless user

    case type
    when :two_factor_login
      return :STATUS_UNSUPPORTED unless user.gh_mobile_auth_enabled?
    when :device_verification, :two_factor_password_reset, :sudo
      return :STATUS_UNSUPPORTED unless can_use_gh_mobile_auth?(user)
    else
      return :STATUS_UNSUPPORTED
    end

    # delete active auth request session values if they are expired - return expired status if this is the case
    return :STATUS_EXPIRED if delete_gh_mobile_auth_session_values_if_expired!(type)

    # check that the user session has successfully initiated a mobile device auth request
    # short circuit a not found status if not
    active_auth_request_id = session[:gh_mobile_request_id]
    return :STATUS_NOT_FOUND unless active_auth_request_id.present?

    req_type = MOBILE_AUTH_TYPES[type]
    # use the partially signed in two factor user ID and the mobile device auth request ID to check the status of the request in authnd
    begin
      response = mobile_device_manager.get_device_auth_status(active_auth_request_id, user.id)
    rescue ::Authnd::Proto::Error, Faraday::Error => err
      # report the error to Sentry
      Failbot.report!(err)
      GitHub.dogstats.increment("mobile_2fa.get_device_auth_status_failure", tags: ["reason:client_raised", "type:#{req_type}"])
      return :STATUS_ERROR
    end

    unless response.result == :RESULT_SUCCESS
      # if the result from authnd was that the request was not found, stop here and clear out the session data
      # for active auth request since it's not an ID that belongs to a request in authnd
      if response.result == :RESULT_FAILED_NOT_FOUND
        delete_gh_mobile_auth_session_values!
        return :STATUS_NOT_FOUND
      end

      # if the result from authnd wasnt success or not found, consider the error as an internal server error
      # don't clear session data here since it could have been an unexpected error in authnd that the next poll could succeed with
      GitHub.dogstats.increment("mobile_2fa.get_device_auth_status_failure", tags: ["reason:#{response.result}", "type:#{req_type}"])
      return :STATUS_ERROR
    end

    # clear out the gh_mobile session values for requests that we're done with
    if [:STATUS_APPROVED, :STATUS_REJECTED, :STATUS_EXPIRED].include? response.status
      delete_gh_mobile_auth_session_values!
    end

    response.status
  end

  private

  def mobile_device_manager
    ::GitHub::Authnd.mobile_device_manager_for("github/account_login")
  end

  # deletes all session values related to GitHub Mobile auth requests IF they are expired
  # returns boolean indicating if the session values were expired and deleted
  def delete_gh_mobile_auth_session_values_if_expired!(type)
    expires_at = session[:gh_mobile_request_expires_at]
    return false unless expires_at.present?

    if Time.now.utc.to_i >= expires_at
      GitHub.dogstats.distribution("mobile_2fa.request_expired_since.dist.time", (Time.now.utc.to_i - expires_at), tags: ["type:#{MOBILE_AUTH_TYPES[type]}"])
      delete_gh_mobile_auth_session_values!
      return true
    end
    false
  end

  # deletes all session values related to GitHub Mobile auth requests
  def delete_gh_mobile_auth_session_values!
    session.delete(:gh_mobile_request_id)
    session.delete(:gh_mobile_challenge)
    session.delete(:gh_mobile_request_expires_at)
  end

  # sets all session values related to GitHub Mobile auth requests
  def set_gh_mobile_auth_session_values(request_id, challenge, expires_at)
    session[:gh_mobile_request_id] = request_id
    session[:gh_mobile_challenge] = challenge
    session[:gh_mobile_request_expires_at] = expires_at.to_i
  end
end
