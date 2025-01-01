# typed: true
# frozen_string_literal: true

module SudoHelper
  extend T::Helpers

  include WebauthnHelper
  include GitHubMobileAuthHelper

  requires_ancestor { ApplicationComponent }

  # https://github.com/brianhempel/hash_to_hidden_fields
  def hash_to_hidden_fields(hash)
    cleaned_hash = hash.reject { |_k, v| v.nil? }
    pairs        = cleaned_hash.to_query.split(Rack::Utils::DEFAULT_SEP)

    tags = pairs.map do |pair|
      key, value = pair.split("=", 2).map { |str| Rack::Utils.unescape(str) }
      hidden_field_tag(key, value)
    end

    safe_join(tags, "\n")
  end

  def sudo_method
    # We don't want to submit creds in a get request
    if request&.get?
      :post
    else
      request&.request_method_symbol
    end
  end

  def sudo_action
    request&.get? ? sudo_url : request&.path
  end

  def redirect_params
    p = request&.parameters.dup
    p.delete "action"
    p.delete "controller"
    p.delete "_method"
    p.delete "authenticity_token"
    p.delete "sudo_password"
    p.delete "webauthn_response"
    p.delete "sudo_app_otp"
    p.delete "sudo_sms_otp"

    # We don't want to submit the user's credentials in a GET request,
    # but it wont work to POST them to a GET endpoint. If the original
    # request was a GET, then we backup the original path
    # and have the credentials POST to 'sessions/sudo'. That endpoint
    # then redirects them to their original destination.
    p["sudo_return_to"] = request&.url if request&.get?
    p["sudo_referrer"] = params[:sudo_referrer] || request&.referrer

    p
  end

  # Is WebAuthn the best initial option for sudo mode?
  # If the user only has passkeys, ensure that they've used one before from this device.
  #
  # Returns boolean.
  def sudo_webauthn_available?
    request_origin_can_support_webauthn?(request) && logged_in? && current_user.has_webauthn_credential?
  end

  # Is GitHub Mobile an option for sudo mode?
  #
  # Returns boolean.
  def sudo_github_mobile_available?
    logged_in? && user_and_session_can_use_gh_mobile_auth?(current_user)
  end

  def sudo_totp_app_available?
    return false unless logged_in?
    return false unless current_user.two_factor_credential.present?
    current_user.two_factor_configured_with?(:app)
  end

  def determine_initial_credential_option(active_credential_option)
    # active_credential_option is used after a user has interacted with the credential options
    # we want to make sure page loads respect this as the "initial" (e.g. if they provide a bad OTP and the page refreshes)
    unless active_credential_option.nil?
      case active_credential_option&.to_sym
      when :webauthn
        return :webauthn if sudo_webauthn_available?
      when :github_mobile
        return :github_mobile if sudo_github_mobile_available?
      when :app
        return :app if sudo_totp_app_available?
      when :password
        return :password
      end
    end

    # if an "active credential option" is not set, we need to
    # direct to the user preference if it's set and available
    # if the preference is set and it happens to be unavailable, we'll fall back to GitHub's preference
    if logged_in? && current_user&.two_factor_credential
      if current_user.two_factor_credential.webauthn_preferred?
        return :webauthn if sudo_webauthn_available?
      elsif current_user.two_factor_credential.github_mobile_preferred?
        return :github_mobile if sudo_github_mobile_available?
      elsif current_user.two_factor_credential.app_preferred?
        return :app if sudo_totp_app_available?
      end
    end

    # if we make it this far direct to the first available method based on our (GitHub's) preference
    if sudo_webauthn_available?
      :webauthn
    elsif sudo_github_mobile_available?
      :github_mobile
    elsif sudo_totp_app_available?
      :app
    else
      :password
    end
  end
end
