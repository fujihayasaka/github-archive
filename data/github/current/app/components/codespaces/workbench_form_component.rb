# typed: true
# frozen_string_literal: true

class Codespaces::WorkbenchFormComponent < ApplicationComponent
  attr_reader :codespace,
              :connection,
              :github_token,
              :github_token_valid_after,
              :service_url,
              :user,
              :already_loading

  DEFAULT_EXTENSIONS = %w[GitHub.vscode-pull-request-github github.github-vscode-theme]

  def initialize(codespace:, github_token:, github_token_valid_after:, user:, user_settings:, connection: nil, already_loading: false, editor: nil)
    @codespace = codespace
    @github_token = github_token
    @github_token_valid_after = github_token_valid_after
    @user = user
    @user_settings = user_settings
    @connection = connection
    @already_loading = already_loading

    query = "editor=#{editor}" if editor

    # The url that the form will POST to.
    base_url = URI.parse(codespace.web_portal_url)
    @service_url = URI::Generic.build(
      scheme: base_url.scheme,
      host: base_url.host,
      port: base_url.port,
      path: "/",
      query: query,
    ).to_s
  end

  def partner_info
    JSON.generate(
      Codespaces::GeneratePortalPartnerInfo.call(
        codespace:,
        github_token:,
        github_token_valid_after:,
        user:,
        user_settings: @user_settings,
        connection:,
      )
    )
  end

end
