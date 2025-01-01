# typed: true
# frozen_string_literal: true

require "oauth_util"

class OauthAccessTokenRequest
  attr_reader :access, :application, :device_authorization_grant, :error_response, :log_data, :params, :entry_point

  BAD_VERIFICATION_CODE        = "#{GitHub.developer_help_url}/apps/managing-oauth-apps/troubleshooting-oauth-app-access-token-request-errors/#bad-verification-code"
  DEVICE_FLOW_ERROR_CODES_URL  = "#{GitHub.developer_help_url}/developers/apps/authorizing-oauth-apps#error-codes-for-the-device-flow"
  INCORRECT_CLIENT_CREDENTIALS = "#{GitHub.developer_help_url}/apps/managing-oauth-apps/troubleshooting-oauth-app-access-token-request-errors/#incorrect-client-credentials"
  REDIRECT_URI_MISMATCH2       = "#{GitHub.developer_help_url}/apps/managing-oauth-apps/troubleshooting-authorization-request-errors/#redirect-uri-mismatch2"
  REDIRECT_URLS                = "#{GitHub.developer_help_url}/apps/building-oauth-apps/authorization-options-for-oauth-apps/#redirect-urls"

  ERROR_CODES_TO_EXCHANGE_ENUMS = {
    bad_verification_code: "INVALID_CODE",
    incorrect_client_credentials: "INVALID_CLIENT_CREDENTIAL",
    refresh_token_success: "SUCCESS",
    refresh_token_invalid_checksum: "INVALID_REFRESH_TOKEN",
    refresh_token_not_found: "REFRESH_TOKEN_NOT_FOUND",
    refresh_token_expired: "REFRESH_TOKEN_EXPIRED",
    refresh_token_mismatched_application: "REFRESH_TOKEN_APPLICATION_MISMATCH",
    incorrect_device_code: "INVALID_DEVICE_CODE",
    access_denied: "DEVICE_AUTHORIZATION_DENIED",
    expired_token: "DEVICE_CODE_EXPIRED",
    unsupported_grant_type: "UNSUPPORTED_GRANT_TYPE",
    redirect_uri_mismatch: "INVALID_REDIRECT_URI",
    redirect_uri_invalid: "INVALID_REDIRECT_URI",
    refresh_token_unknown: "UNKNOWN_FAILURE",
    device_flow_disabled: "DEVICE_FLOW_DISABLED",
    unverified_user_email: "INVALID_USER_EMAIL",
    # INTERNAL_APP_FAILURES - these are in app/models/oauth_access/provider.rb
    token_creation_failure: "INTERNAL_APP_FAILURE",
    installation_creation_failed: "INTERNAL_APP_FAILURE",
    invalid_token: "INTERNAL_APP_FAILURE",
    installation_missing_access: "INTERNAL_APP_FAILURE",
    missing_repository: "INTERNAL_APP_FAILURE",
    repository_not_found: "INTERNAL_APP_FAILURE",
    sso_required: "INTERNAL_APP_FAILURE"
  }

  def self.process(application, log_data, params, entry_point:)
    new(application, log_data, params, entry_point).process
  end

  def initialize(application, log_data, params, entry_point)
    @application = application
    @log_data    = log_data
    @params      = params
    @entry_point = entry_point
  end

  def process
    access, error_response = case params[:grant_type]
    when DeviceAuthorizationGrant::GRANT_TYPE
      device_access_lookup
    when RefreshToken::GRANT_TYPE
      refresh_token_access_lookup
    else
      oauth_flow_access_lookup
    end

    if validate_redirect_uri?(access)
      unless redirect_uri_matches_request?(access)
        error_response = {
          error: :redirect_uri_mismatch,
          error_description: "The redirect_uri MUST match the callback URL provided during authorization.",
          error_uri: REDIRECT_URI_MISMATCH2,
        }
      end
    end

    if access&.user&.should_verify_email?
      unless access.user.primary_user_email.verified?
        error_response = {
          error: :unverified_user_email,
          error_description: "The user must have a verified primary email",
          # FIXME: link to appropriate docs
          error_uri: INCORRECT_CLIENT_CREDENTIALS,
        }
      end
    end

    if error_response
      publish_token_exchange_failure_hydro_message(error_response: error_response, access: access, application: application)
      return log_error(error_response)
    end

    if @refresh_token
      log_data[:refresh_token] = secret_last_eight(params[:refresh_token])
      token, refresh_token = @refresh_token.redeem(entry_point: entry_point)
      @refresh_token.reload
      access = @refresh_token.refreshable

      publish_token_exchange_hydro_message(
        token_last_eight: secret_last_eight(token),
        refresh_token_last_eight: secret_last_eight(refresh_token),
        access: access
      )

      response = {
        access_token: token,
        expires_in: access.expires_in,
        refresh_token: refresh_token,
        refresh_token_expires_in: @refresh_token&.expires_in,
        scope: access.access_level.join(","),
        token_type: :bearer,
      }

      if GitHub.multi_tenant_enterprise?
        response[:github_host] = GitHub.host_name_with_tenant
      end

      return response
    end

    _, error_response = application.grant_repository_scoped_installation_on(access, repository_id: params[:repository_id])
    if error_response
      publish_token_exchange_failure_hydro_message(error_response: error_response, access: access, application: application)
      return log_error(error_response)
    end

    # https://github.com/github/ecosystem-apps/issues/1716#issuecomment-960178773
    begin
      token, refresh_token = access.redeem
    rescue ActiveRecord::RecordNotUnique
      error_response = bad_verification_code_error

      publish_token_exchange_failure_hydro_message(error_response: error_response, access: access, application: application)
      return log_error(error_response)
    end

    response_options = {}.tap do |opts|
      opts[:access_token] = token

      if refresh_tokens_enabled?
        opts[:expires_in] = access.expires_in
        opts[:refresh_token] = refresh_token
        opts[:refresh_token_expires_in] = access.refresh_token&.expires_in
      end

      opts[:token_type] = :bearer
      opts[:scope] = access.access_level.join(",")

      if GitHub.multi_tenant_enterprise?
        opts[:github_host] = GitHub.host_name_with_tenant
      end

      if (installation = access.installation)
        if installation.repositories.any?
          opts[:repos_url] = Api::Serializer.url("/user/repos")
        end

        opts[:permissions] = installation.permissions
      end
    end

    if should_trigger_auto_install_on_oauth_code_exchange?
      AutomaticAppInstallation.trigger(
        type:       :oauth_code_exchanged,
        actor:      access.user,
        originator: application,
      )
    end

    publish_token_exchange_hydro_message(
      token_last_eight: secret_last_eight(token),
      refresh_token_last_eight: secret_last_eight(refresh_token),
      access: access
    )
    response_options
  end

  private

  def device_access_lookup
    hashed_code = DeviceAuthorizationGrant.hash_for(params[:device_code])
    device_authorization_grant = DeviceAuthorizationGrant.find_by(
      hashed_device_code: hashed_code,
      application: @application
    )

    error_response = case
    when DeviceAuthorizationRequest.device_flow_disabled?(application: @application)
      {
        error: :device_flow_disabled,
        error_description: "This application has not enabled authorization via the device flow.",
        error_uri: DEVICE_FLOW_ERROR_CODES_URL,
      }
    when device_authorization_grant.nil?
      {
        error: :incorrect_device_code,
        error_description: "The device_code provided is not valid.",
        error_uri: DEVICE_FLOW_ERROR_CODES_URL,
      }
    when device_authorization_grant.access_denied?
      {
        error: :access_denied,
        error_description: "The authorization request was denied.",
        error_uri: DEVICE_FLOW_ERROR_CODES_URL,
      }
    when device_authorization_grant.expired?
      {
        error: :expired_token,
        error_description: "This 'device_code' has expired.",
        error_uri: DEVICE_FLOW_ERROR_CODES_URL,
      }
    when !device_authorization_grant.claimed?
      {
        error: :authorization_pending,
        error_description: "The authorization request is still pending.",
        error_uri: DEVICE_FLOW_ERROR_CODES_URL,
      }
    end

    [device_authorization_grant&.oauth_access, error_response]
  end

  def refresh_token_access_lookup
    @refresh_token_lookup = RefreshToken.for_plaintext_token(params[:refresh_token], application: application)
    @refresh_token = @refresh_token_lookup.token

    if @refresh_token
      if (access = @refresh_token.refreshable)
        device_authorization_grant = access.device_authorization_grant
      end
    end

    client_secret_valid = application.validate_client_secret(params[:client_secret])

    error_response = if !client_secret_valid && device_authorization_grant.nil?
      incorrect_client_credentials_error
    elsif @refresh_token.nil? && params.has_key?(:refresh_token)
      GitHub.dogstats.increment "oauth", tags: ["action:access_token", "error:bad_refresh_token"]

      log_data.merge!(
        :refresh_token => secret_last_eight(params[:refresh_token]),
        application_key => application.id
      )

      {
        error: :bad_refresh_token,
        error_description: "The refresh token passed is incorrect or expired.",
        # FIXME: link to appropriate docs
        error_uri: BAD_VERIFICATION_CODE,
      }
    end

    [access, error_response]
  end

  def oauth_flow_access_lookup
    redirect_uri, error_response = get_redirect_uri(application, params[:redirect_uri])
    if error_response
      publish_token_exchange_failure_hydro_message(error_response: error_response, access: access, application: application)
      return [nil, log_error(error_response)]
    end

    access = application.access_for_code(params[:code])

    client_secret_valid = application.validate_client_secret(params[:client_secret])

    error_response = if !client_secret_valid
      incorrect_client_credentials_error
    elsif !valid_redirect_uri?(application, redirect_uri)
      {
        error: :redirect_uri_mismatch,
        error_description: "The redirect_uri MUST match the registered callback URL for this application.",
        error_uri: REDIRECT_URI_MISMATCH2,
      }
    elsif access.nil? && !params.has_key?(:refresh_token)
      bad_verification_code_error
    elsif params.has_key?(:refresh_token)
      {
        error: :unsupported_grant_type,
        error_description: "You must specify grant_type of refresh_token when using a refresh_token.",
        # FIXME: link to appropriate docs
        error_uri: BAD_VERIFICATION_CODE,
      }
    end

    [access, error_response]
  end

  def application_key
    return @application_key if defined?(@application_key)
    @application_key = application.class.name.underscore.to_sym
  end

  def get_redirect_uri(application, redirect_uri)
    # Only normalize applications with one callback URL to maintain legacy
    # behavior for existing applications.
    normalize = !application.strict_callback_url_validation?

    if redirect_uri.blank?
      [application.try(:callback_url), nil]
    elsif normalize
      [Addressable::URI.parse(redirect_uri).normalize.to_s, nil]
    else
      [redirect_uri, nil]
    end
  rescue Addressable::URI::InvalidURIError
    [nil, {
      error: :redirect_uri_invalid,
      error_description: "The redirect_uri MUST be a valid URL.",
      error_uri: REDIRECT_URLS,
    }]
  end

  def publish_token_exchange_failure_hydro_message(error_response:, access:, application:)
    return if error_response[:error] == :authorization_pending

    application ||= access&.application
    message = { oauth_access: access, application: application }

    lookup_key = if @refresh_token_lookup && !(@refresh_token_lookup.reason == :success)
      :"refresh_token_#{@refresh_token_lookup.reason}"
    else
      error_response[:error]
    end

    message[:exchanged_refresh_token_last_eight] = secret_last_eight(params[:refresh_token]) if params[:refresh_token]
    message[:exchange_result] = ERROR_CODES_TO_EXCHANGE_ENUMS[lookup_key]

    GlobalInstrumenter.instrument("oauth_access.exchange", message)
  end

  def publish_token_exchange_hydro_message(token_last_eight:, refresh_token_last_eight: nil, access:)
    message = {
      application: access.application,
      oauth_access: access,
      token_last_eight: token_last_eight,
      refresh_token_last_eight: refresh_token_last_eight,
      exchange_result: "SUCCESS"
    }
    if params[:refresh_token]
      message[:exchanged_refresh_token_last_eight] = secret_last_eight(params[:refresh_token])
    end

    GlobalInstrumenter.instrument("oauth_access.exchange", message)
  end

  def refresh_tokens_enabled?
    application.is_a?(Integration) && application.user_token_expiration_enabled?
  end

  def should_trigger_auto_install_on_oauth_code_exchange?
    Apps::Privileged.capable?(:can_auto_install_apps_on_oauth_code_exchanged, app: application)
  end

  def secret_last_eight(secret)
    secret = secret.to_s
    return secret if secret.length < 8

    secret.to_s[-8..-1]
  end

  def log_error(error_response)
    log_data[:error] = error_response[:error]
    error_response
  end

  def incorrect_client_credentials_error
    {
      error: :incorrect_client_credentials,
      error_description: "The client_id and/or client_secret passed are incorrect.",
      error_uri: INCORRECT_CLIENT_CREDENTIALS,
    }
  end

  def valid_redirect_uri?(application, redirect_uri)
    OauthUtil.valid_redirect_uri?(application, redirect_uri)
  rescue ArgumentError
    false
  end

  def validate_redirect_uri?(access)
    return false unless access
    # If they don't specify a redirect URI in the initial request we don't validate it.
    return false unless access.requested_redirect_uri

    true
  end

  def redirect_uri_matches_request?(access)
    normalize = !access.application.strict_callback_url_validation?
    redirect_uri = params[:redirect_uri]

    uri = if redirect_uri
      normalize ? Addressable::URI.parse(redirect_uri).normalize.to_s : redirect_uri
    end

    requested_uri_matches_uri = access.requested_redirect_uri == uri
    tags = ["result:#{requested_uri_matches_uri ? "match" : "mismatch"}"]
    GitHub.dogstats.increment("oauth_access_token_request.redirect_uri_validation", tags: tags)

    if GitHub.flipper[:code_exchange_redirect_uri_compare].enabled?(access.application)
      requested_uri_matches_uri
    else
      true
    end
  end

  def bad_verification_code_error
    GitHub.dogstats.increment "oauth", tags: ["action:authorize", "error:bad_code"]
    log_data.merge!(
      :verification_code => secret_last_eight(params[:code]),
      :passed_callback => params[:redirect_uri],
      application_key => application.id,
    )

    {
      error: :bad_verification_code,
      error_description: "The code passed is incorrect or expired.",
      error_uri: BAD_VERIFICATION_CODE,
    }
  end
end
