# typed: true
# frozen_string_literal: true

class OauthAuthorizationServerController < ApplicationController
  before_action :check_oauth_discovery_enabled, only: [:oauth_authorization_server]
  skip_before_action :perform_conditional_access_checks # rubocop:disable GitHub/DoNotSkipCapBeforeAction

  depends_on_clusters ApplicationRecord::Mysql1,
    only: [:oauth_authorization_server]

  def oauth_authorization_server # rubocop:todo GitHub/UseRestfulActions
    msg = {
      # TODO add GHES/GHE.com support.
      issuer: "https://github.com/login/oauth",
      authorization_endpoint: "https://github.com/login/oauth/authorize",
      token_endpoint: "https://github.com/login/oauth/access_token",
      response_types_supported: %w[code],
      grant_types_supported: %w[authorization_code],
      service_documentation: "https://docs.github.com/en/apps/creating-github-apps/registering-a-github-app/registering-a-github-app",
      code_challenge_methods_supported: %w[S256],
    }

    render json: msg, status: :ok
  end

  private

  def check_oauth_discovery_enabled
    render_404 unless GitHub.flipper[:copilot_mcp_oauth_discovery].enabled?
  end
end
