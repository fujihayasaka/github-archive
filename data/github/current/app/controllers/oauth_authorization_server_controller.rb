# typed: true
# frozen_string_literal: true

class OauthAuthorizationServerController < ApplicationController
  before_action :check_oauth_discovery_enabled, only: [:oauth_authorization_server]
  skip_before_action :perform_conditional_access_checks # rubocop:disable GitHub/DoNotSkipCapBeforeAction

  depends_on_clusters ApplicationRecord::Mysql1,
    only: [:oauth_authorization_server]

  def oauth_authorization_server # rubocop:todo GitHub/UseRestfulActions
    msg = {
      issuer: issuer,
      authorization_endpoint: authorization_endpoint,
      token_endpoint: token_endpoint,
      response_types_supported: %w[code],
      grant_types_supported: %w[authorization_code],
      service_documentation: "#{GitHub.developer_help_url}/apps/creating-github-apps/registering-a-github-app/registering-a-github-app",
      code_challenge_methods_supported: %w[S256],
    }

    render json: msg, status: :ok
  end

  private

  def issuer
    "#{GitHub.url}/login/oauth"
  end

  def authorization_endpoint
    "#{issuer}/authorize"
  end

  def token_endpoint
    "#{issuer}/access_token"
  end

  def check_oauth_discovery_enabled
    render_404 unless FeatureFlag.vexi.enabled?(:copilot_mcp_oauth_discovery, default: false)
  end
end
