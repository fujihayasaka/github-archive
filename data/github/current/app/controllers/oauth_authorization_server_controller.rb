# typed: true
# frozen_string_literal: true

class OauthAuthorizationServerController < ApplicationController
  skip_before_action :perform_conditional_access_checks # rubocop:disable GitHub/DoNotSkipCapBeforeAction

  depends_on_clusters ApplicationRecord::Mysql1,
    only: [:oauth_authorization_server]

  def oauth_authorization_server # rubocop:todo GitHub/UseRestfulActions
    msg = {
      issuer: issuer,
      authorization_endpoint: authorization_endpoint,
      token_endpoint: token_endpoint,
      response_types_supported: %w[code],
      grant_types_supported: grant_types_supported,
      service_documentation: "#{GitHub.developer_help_url}/apps/creating-github-apps/registering-a-github-app/registering-a-github-app",
      code_challenge_methods_supported: %w[S256],
    }

    if updated_discovery_documents?
      msg[:device_authorization_endpoint] = device_authorization_endpoint
      msg[:authorization_response_iss_parameter_supported] = true
    end

    render json: msg, status: :ok
  end

  private

  def updated_discovery_documents?
    FeatureFlag.vexi.enabled?(:oidc_discovery_dynamic_issuer, default: false)
  end

  def grant_types_supported
    if updated_discovery_documents?
      %w[authorization_code refresh_token urn:ietf:params:oauth:grant-type:device_code]
    else
      %w[authorization_code refresh_token]
    end
  end

  def device_authorization_endpoint
    "#{GitHub.url}/login/device/code"
  end

  def issuer
    "#{GitHub.url}/login/oauth"
  end

  def authorization_endpoint
    "#{issuer}/authorize"
  end

  def token_endpoint
    "#{issuer}/access_token"
  end
end
