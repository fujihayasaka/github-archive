# typed: true
# frozen_string_literal: true

class DeviceAuthorizationRequest
  attr_reader :application, :ip_address, :params

  include UrlHelpers

  OAUTH_APPLICATION_SUSPENDED = "#{GitHub.developer_help_url}/apps/managing-oauth-apps/troubleshooting-authorization-request-errors/#application-suspended"
  GITHUB_APP_SUSPENDED = "#{GitHub.developer_help_url}/apps/using-github-apps/authorizing-github-apps"

  def self.verification_uri
    "#{GitHub.scheme}://#{GitHub.host_name_with_tenant}/login/device"
  end

  def self.process(application, params, ip_address)
    new(application, params, ip_address).process
  end

  def self.device_flow_disabled?(application:)
    return false unless application.respond_to?(:device_flow_enabled?)

    !application.device_flow_enabled?
  end

  def initialize(application, params, ip_address)
    @application = application
    @ip_address  = ip_address
    @params      = params
  end

  def process
    error_response = case
    when application.suspended?
      error_uri = application.is_a?(Integration) ? GITHUB_APP_SUSPENDED : OAUTH_APPLICATION_SUSPENDED
      error_description = "Your application has been suspended. Please visit #{contact_url(host: GitHub.host_name_with_tenant)}."
      {
        error: :application_suspended,
        error_description: error_description,
        error_uri: error_uri,
      }
    when invalid_scopes?
      {
        error: :invalid_scope,
        error_description: invalid_scopes_error_description,
        error_uri: GitHub.developer_help_url,
      }
    when self.class.device_flow_disabled?(application: application)
      {
        error: :device_flow_disabled,
        error_description: "Device Flow must be explicitly enabled for this App",
        error_uri: GitHub.developer_help_url,
      }
    end

    return error_response if error_response

    grant, error_response = create_device_authorization_grant
    return error_response if error_response

    device_code, error_response = redeem_device_code(grant)
    return error_response if error_response

    {
      device_code: device_code,
      user_code: grant.user_code,
      verification_uri: self.class.verification_uri,
      expires_in: grant.expires_in,
      interval: ::DeviceAuthorizationGrant::INTERVAL
    }
  end

  private

  def create_device_authorization_grant
    DeviceAuthorizationGrant.create!(application: application, scopes: scopes, ip: ip_address)
  rescue ActiveRecord::RecordInvalid
    [nil, {
      error: :request_failed,
      error_description: "The request failed to be processed, please try again",
    }]
  end

  def invalid_scopes
    @_invalid_scopes ||= if !params.key?(:scope) || application.is_a?(Integration)
      []
    else
      names = params[:scope]

      # Take the `scope` param and clean it up
      # without filtering it.
      #
      # From https://github.com/github/egress/blob/722a29f4acfebf66615bd5c675fb31f7935d41c8/lib/egress/dsl.rb
      #
      # Clean, dedupe, filter.
      names = names.to_s.split(/,|\A|\s/).delete_if do |name|
        name.strip!; name.downcase!
        name.nil? || name.empty?
      end.uniq.sort

      OauthAccessTokens::Domain.invalid_scopes(names)
    end
  end

  def invalid_scopes?
    invalid_scopes.any?
  end

  def invalid_scopes_error_description
    "The scopes requested are invalid: #{invalid_scopes.to_sentence}."
  end

  def redeem_device_code(device_authorization_grant)
    device_code = device_authorization_grant.redeem_device_code!

    [device_code, nil]
  rescue ActiveRecord::RecordInvalid
    [nil, {
      error: :request_failed,
      error_description: "The request failed to be processed, please try again",
    }]
  end

  def scopes
    return @scopes if defined?(@scopes)
    @scopes = OauthAccessTokens::Domain.normalize_scopes(params[:scope])

    # Stop users from requesting valid hidden scopes on dotcom.
    # See https://github.com/github/appsec-reviews/issues/482 for more details.
    unless GitHub.enterprise?
      valid_hidden_scopes = OauthAccess.valid_hidden_scopes(nil)
      @scopes.reject! { |scope| valid_hidden_scopes[scope] == false }
    end

    @scopes
  end
end
