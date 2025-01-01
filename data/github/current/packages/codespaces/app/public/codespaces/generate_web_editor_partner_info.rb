# typed: true # rubocop:todo Sorbet/StrictSigil
# frozen_string_literal: true

module Codespaces
  # Generate a version of the PartnerInfo payload specific to the Lightweight
  # Web Editor (github.dev) auth process.  See
  # https://aka.ms/vscs-platform-json-schema-webeditor for the schema.
  class GenerateWebEditorPartnerInfo < Command
    include UrlHelpers

    def initialize(user:, token:, host:)
      @user = user
      @token = token
      @host = host
    end

    def perform

      credentials = if GitHub.flipper[:codespaces_clean_up_partner_info].enabled?(@user)
        [
          {
            token: @token,
            host: @host,
          }
        ]
      else
        [{
          token: @token,
          host: @host,
          path: "/"
        },
        {
          token: @token,
          host: @host,
        }]
      end

      JSON.generate({
        partnerName: "github",
        managementPortalUrl: auth_github_editor_url(host: @host),
        credentials: credentials,
        favicon: {
          stable: "https://github.com/favicons/favicon-codespaces.svg",
          insider: "https://github.com/favicons/favicon-codespacesinsider.svg"
        },
        vscodeSettings: vscode_settings,
        featureFlags: Codespaces::Vscs.feature_flags(@user),
      })
    end

    private

    def vscode_settings
      Codespaces::Settings.for_user(@user).vscode_settings(
        codespaces_home_url: "https://github.com",
        github_token: @token,
        user: @user,
      ).tap do |settings|
        # Web editor needs one additional authSession beyond what codespaces gets.
        settings.fetch(:defaultAuthSessions) << {
          type: "github",
          id: "github-session-vscode-remotehub",
          accessToken: @token,
          account: {
            id: @user.id.to_s,
            label: @user.display_login
          },
          scopes: ["repo"]
        }
      end
    end
  end
end
