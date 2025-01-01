# typed: true # rubocop:todo Sorbet/StrictSigil
# frozen_string_literal: true

module Codespaces
  class GeneratePortalPartnerInfo < Command
    include GitHub::Memoizer
    include UrlHelpers
    include UrlHelper

    COPILOT_EXTENSION_ID = "GitHub.copilot"

    attr_reader :user, :codespace, :github_token, :github_token_valid_after, :cascade_token, :user_settings, :connection

    def initialize(user:, codespace:, github_token:, github_token_valid_after:, cascade_token:, user_settings:, connection:, host: GitHub.host_name)
      @user = user
      @codespace = codespace
      @github_token = github_token
      @github_token_valid_after = github_token_valid_after
      @cascade_token = cascade_token
      @user_settings = user_settings
      @host = host
      @connection = connection
    end

    def perform
      credentials = [
        {
          token: github_token,
          host: @host,
          validAfter: github_token_valid_after
        }
      ]

      partner_info = {
        partnerName: "github",
        managementPortalUrl: auth_redirect_codespaces_url(host: @host),
        codespaceId: codespace.guid,
        connectionInfo: connection,
        credentials: credentials,
        favicon: {
          stable: "https://github.com/favicons/favicon-codespaces.svg",
          insider: "https://github.com/favicons/favicon-codespacesinsider.svg"
        },
        featureFlags: Codespaces::Vscs.feature_flags(user),
        vscodeSettings: vscode_settings,
        gitHubApiUrl: Codespaces.monolith_url_builder.api_url,
        workbenchType: "codespaces",
        name: codespace.name,
        displayName: codespace.safe_display_name,
        workspaceCustomizations: workspace_customizations,
      }

      if fetch_cascade_token?
        # Cascade token used to authenticate on the VSCS side. `CASCADE_TOKEN_PLACEHOLDER` is replaced with the token in a typescript callback.
        partner_info[:codespaceToken] = cascade_token || "%CASCADE_TOKEN_PLACEHOLDER%"
      end

      partner_info
    end

    private

    def codespaces_home_url
      if codespace.pull_request_with_fallback.present?
        show_pull_request_url(codespace.repository.owner, codespace.repository, codespace.pull_request, host: @host)
      else
        repository_url(codespace.repository)
      end
    end

    def vscode_settings
      default_extensions = Codespaces::Settings::DEFAULT_EXTENSIONS.dup
      if Copilot::User.new(user).codespaces_demo_usage_allowed?(codespace)
        default_extensions << COPILOT_EXTENSION_ID
      end

      user_settings.vscode_settings(codespaces_home_url: codespaces_home_url, github_token: github_token, user: user, open_files_specified: open_files_specified?, default_extensions:)
    end

    def workspace_customizations
      # Avoid grabbing all of customizations.codespaces since it could be pretty big. Just grab the properties we
      # care about.
      {
        openFiles: codespace.dev_container&.dig("customizations", "codespaces", "openFiles"),
      }
    rescue Codespaces::DevContainer::ReadError => e
      nil
    end

    def fetch_cascade_token?
      !user.feature_enabled?(:codespaces_skip_minting_cascade_token)
    end

    def open_files_specified?
      return false unless workspace_customizations
      !workspace_customizations[:openFiles].nil?
    end
  end
end
