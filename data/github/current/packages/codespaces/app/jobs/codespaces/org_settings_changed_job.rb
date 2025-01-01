# typed: true
# frozen_string_literal: true

class Codespaces::OrgSettingsChangedJob < CodespacesJob
  locked_by timeout: 1.minute, key: DEFAULT_LOCK_PROC
  retry_on_dirty_exit
  retry_on_recoverable_exceptions

  def perform(event_type:, context:, actor_id:)
    case event_type
    when Codespaces::Events::ORG_CODESPACES_ENABLED, Codespaces::Events::ORG_CODESPACES_DISABLED
      GlobalInstrumenter.instrument(event_type, { actor_id: actor_id, organization_id: context })
    when Codespaces::Events::ORG_REPO_OWNED_CODESPACES_ENABLED, Codespaces::Events::ORG_REPO_OWNED_CODESPACES_DISABLED
      GlobalInstrumenter.instrument(event_type, { actor_id: actor_id, organization_id: context })
    when Codespaces::Events::ORG_CODESPACES_ENABLED_USER, Codespaces::Events::ORG_CODESPACES_DISABLED_USER
      GlobalInstrumenter.instrument(event_type, { actor_id: actor_id, user_id: context })
    when Codespaces::Events::ORG_CODESPACES_ENABLED_TEAM, Codespaces::Events::ORG_CODESPACES_DISABLED_TEAM
      GlobalInstrumenter.instrument(event_type, { actor_id: actor_id, team_id: context })
    when Codespaces::Events::ORG_CODESPACES_OWNERSHIP_SETTING_UPDATED
      GlobalInstrumenter.instrument(event_type, { actor_id: actor_id, organization_id: context })
    end
  end
end
