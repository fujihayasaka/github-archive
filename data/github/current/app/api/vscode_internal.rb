# typed: true
# frozen_string_literal: true

class Api::VscodeInternal < Api::App
  READ_MODE_SCOPES = ["settings:read", "extensions:read", "keybindings:read", "snippets:read", "globalState:read", "machines:read", "tasks:read", "profiles:read", "prompts:read", "mcp:read", "editSessions:read"].freeze
  WRITE_MODE_SCOPES = ["settings", "extensions", "keybindings", "snippets", "globalState", "machines", "tasks", "profiles", "prompts", "mcp", "editSessions:read"].freeze

  # VS LiveShare and Settings Sync use this endpoint to validate that the token
  # is from the VS Code auth server. They cannot use `POST applications/:client_id/token`
  # because they do not have the client secret. See https://github.com/github/codespaces/issues/1675
  # for more context.
  post "/vsc_internal/validate", operation_id: :internal do
    @route_owner = "@github/codespaces"
    control_access :codespace_user,
      resource: current_user,
      allow_integrations: false,
      allow_user_via_granular_actor: true

    # scopes should be an empty array if feature flag is disabled to maintain the same behavior
    scopes = []
    if Apps::Privileged.capable?(:codespaces_settings_sync, app: current_user.oauth_access.integration)
      if current_user.codespaces_settings_sync_authorization == Configurable::CodespacesSettingsSyncAuthorization::DISABLED
        scopes = nil
      elsif !current_user.oauth_access.installation.present?
        # Settings sync is enabled, but the user is not authenticating with a repo-scoped token, so return read-only scopes
        scopes = READ_MODE_SCOPES
      else
        repository = Codespace.find_by(id: current_user.oauth_access.installation.codespace_ids.first)&.repository
        deliver_error! 403 if repository.nil?

        # Check that the repository is in the authorizations
        if current_user.trusted_repository_authorizations.find_by(repository_id: repository.id) || current_user.codespaces_repository_authorization == Configurable::CodespacesRepositoryAuthorization::ALL_REPOSITORIES
          scopes = WRITE_MODE_SCOPES
        else
          scopes = READ_MODE_SCOPES
        end
      end
    end

    # Add scopes array to the response
    deliver :settings_sync_hash, {
      current_user: current_user,
      scopes: scopes,
    }
  end
end
