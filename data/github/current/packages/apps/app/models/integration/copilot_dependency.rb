# typed: true
# frozen_string_literal: true

module Integration::CopilotDependency
  extend T::Helpers

  # Values defined by PREVIEW_SUBJECTS_AND_FEATURE_FLAGS in User::Resources
  COPILOT_PERMISSION = "copilot_messages"

  requires_ancestor { Integration }

  delegate :enable_copilot_listing!, :disable_copilot_listing!, to: :marketplace_listing, allow_nil: true

  def agent_enabled?
    owner.feature_enabled?(:copilot_extendable)
  end

  def oidc_settings_enabled?
    owner.feature_enabled?(:enable_agents_oidc_settings)
  end

  def copilot_extension_skills_enabled?
    owner.feature_enabled?(:copilot_extension_skills_enabled)
  end

  def agent_configured?(version = latest_version)
    return false unless integration_agent.present?
    return false if T.must(integration_agent).app_type == "disabled"

    permissions = version.permissions_of_type(User).keys
    permissions.include?(COPILOT_PERMISSION)
  end

  def copilot_messages_enabled?(version = latest_version)
    permissions = version.permissions_of_type(User).keys
    permissions.include?(COPILOT_PERMISSION)
  end
end
