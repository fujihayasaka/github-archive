# typed: true
# frozen_string_literal: true

module Integration::CopilotDependency
  extend T::Helpers

  # Values defined by PREVIEW_SUBJECTS_AND_FEATURE_FLAGS in User::Resources
  COPILOT_PERMISSION = "copilot_messages"

  requires_ancestor { Integration }

  delegate :enable_copilot_listing!, :disable_copilot_listing!, to: :marketplace_listing, allow_nil: true

  def oidc_settings_enabled?
    owner.feature_enabled?(:enable_agents_oidc_settings)
  end

  def copilot_extension_skills_enabled?
    owner.feature_enabled?(:copilot_extension_skills_enabled)
  end

  def agent_configured?(specified_version = nil)
    async_integration_agent.then do |agent|
      return false unless agent.present?
      return false if T.must(agent).app_type == "disabled"
    end.sync

    async_latest_version.then do |latest|
      version = specified_version || latest
      permissions = version&.permissions_of_type(User)&.keys
      permissions.include?(COPILOT_PERMISSION)
    end.sync
  end

  def copilot_messages_enabled?(version = latest_version)
    permissions = version.permissions_of_type(User).keys
    permissions.include?(COPILOT_PERMISSION)
  end

  sig { returns(String) }
  def enable_copilot_listing_errors
    return "" unless marketplace_listing.present?
    return "Cannot enable Copilot for a Marketplace listing with paid plans" if T.must(marketplace_listing).published_paid_plans?

    ""
  end
end
