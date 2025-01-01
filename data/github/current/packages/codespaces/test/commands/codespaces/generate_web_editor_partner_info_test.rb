# typed: true
# frozen_string_literal: true

require "test_helper"

class Codespaces::GenerateWebEditorPartnerInfoCommandTest < GitHub::TestCase
  include GitHub::ComponentTestHelpers

  fixtures do
    @user = create :user
    @connection = { "sessionId" => "123", "relaySas" => "hi", "relayEndpoint" => "https://vsc", "sessionToken" => "abc23", "hostPublicKeys" => ["key1"], "serviceUri" => "https://vsc/service-uri" }
    GitHub.flipper[:codespaces_clean_up_partner_info].enable
  end

  test "renders form for vscs authentication" do
    as @user

    github_token = "abcdefg"
    host = "github.localhost"

    command = Codespaces::GenerateWebEditorPartnerInfo.new(
      user: @user,
      token: github_token,
      host: host,
    )

    expected = command.perform

    partner_info = partner_info(token: github_token, user: @user, host: host)

    auth_sessions = partner_info[:vscodeSettings][:defaultAuthSessions]
    partner_info[:vscodeSettings][:defaultAuthSessions] = auth_sessions
    assert_equal expected, partner_info.to_json
  end

  test "renders form in proxima", skip_enterprise: true do
    emu = create(:emu)
    business = emu.enterprise_managed_business

    on_multi_tenant_enterprise(tenant: business) do
      as emu

      github_token = "abcdefg"
      host = "github.localhost"

      command = Codespaces::GenerateWebEditorPartnerInfo.new(
        user: emu,
        token: github_token,
        host: host,
      )

      expected = JSON.parse(command.perform)

      expected["vscodeSettings"]["defaultAuthSessions"].each do |session|
        assert_equal session["account"]["label"], emu.display_login
      end
    end
  end

  test "includes feature flags in the payload" do
    as @user

    github_token = "abcdefg"
    host = "github.localhost"

    command = Codespaces::GenerateWebEditorPartnerInfo.new(
      user: @user,
      token: github_token,
      host: host,
    )

    expected = JSON.parse(command.perform)

    refute_nil expected["featureFlags"]
  end

  def feature_flags_for_user(user)
    {
      "developer": GitHub.flipper[:codespaces_developer].enabled?(user),
    }
  end

  def partner_info(token:, user:, host:)
    auth_sessions = [
      {
        type: "github",
        id: "github-session-sync-service",
        accessToken: token,
        account: {
          id: user.id.to_s,
          label: user.login
        },
        scopes: ["user:email"],
      },
      {
        type: "github",
        id: "github-session-codespaces-extension",
        accessToken: token,
        account: {
          id: @user.id.to_s,
          label: @user.login
        },
        scopes: ["read:user", "user:email", "repo", "codespace"].sort
      },
      {
        type: "github",
        id: "github-session-vs-codespaces",
        accessToken: token,
        account: {
          id: user.id.to_s,
          label: user.login
        },
        scopes: ["read:user", "user:email", "repo"].sort
      },
      {
        type: "github",
        id: "github-session-ghpr-ghr",
        accessToken: token,
        account: {
          id: user.id.to_s,
          label: user.login
        },
        scopes: ["read:user", "user:email", "repo", "workflow"].sort
      },
      {
        type: "github",
        id: "github-session-github-copilot",
        accessToken: token,
        account: {
          id: user.id.to_s,
          label: user.login
        },
        scopes: ["read:user"],
      },
      {
        type: "github",
        id: "github-session-vs-code-auth",
        accessToken: token,
        account: {
          id: user.id.to_s,
          label: user.login
        },
        scopes: %w[repo workflow],
      },
      {
        type: "github",
        id: "github-session-vscode-remotehub",
        accessToken: token,
        account: {
          id: user.id.to_s,
          label: user.login
        },
        scopes: ["repo"],
      }
    ]

    {
      "partnerName": "github",
      managementPortalUrl: "http://#{host}/auth/github_editor",
      credentials: [{
        token: token,
        host: host,
      }],
      favicon: {
        stable: "https://github.com/favicons/favicon-codespaces.svg",
        insider: "https://github.com/favicons/favicon-codespacesinsider.svg"
      },
      vscodeSettings: {
        vscodeChannel: "stable",
        enableSyncByDefault: false,
          homeIndicator: {
            icon: "github-inverted",
            href: "https://github.com",
            title: "Go Home"
          },
          defaultSettings: {
            "workbench.startupEditor": "readme",
            "telemetry.telemetryLevel": "all",
            "github.codespaces.authProvider": "github",
          },
          defaultExtensions: [
            { id: "GitHub.vscode-pull-request-github" },
            { id: "github.github-vscode-theme" }
          ],
          defaultAuthSessions: auth_sessions,
          authenticationSessionId: "github-session-sync-service",
          settingsSync: user.codespaces_settings_sync_authorization
      },
      featureFlags: Codespaces::Vscs.feature_flags(user)
    }
  end
end
