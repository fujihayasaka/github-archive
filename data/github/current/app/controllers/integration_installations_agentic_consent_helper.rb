# typed: true
# frozen_string_literal: true

# Shared helper for persisting `Copilot::IntegrationInstallationAgentConsent`
# records based on the consent params used by install/update forms and the
# show-page agent consent endpoint. Callers are responsible for gating the call
# on their own visibility predicate (install vs update).
module IntegrationInstallationsAgenticConsentHelper
  extend ActiveSupport::Concern
  extend T::Helpers

  requires_ancestor { ApplicationController }

  private

  def current_user_can_manage_agentic_consent_for?(target, integration: nil)
    return false if target.nil?

    return target.adminable_by?(current_user) if target.organization?
    return false if integration.nil?

    integration.installable_on_by?(target: target, actor: current_user)
  end

  # Returns:
  # - truthy when consent state was updated (or was already correct)
  # - `false` when the underlying ActiveRecord operation raised
  def persist_agentic_consent(installation)
    return false unless current_user_can_manage_agentic_consent_for?(installation.target, integration: installation.integration)

    enable = params[:enable_agentic_features] == "1" || params[:value] == "1"
    if enable
      return true if installation.agent_consent.present?

      Copilot::IntegrationInstallationAgentConsent.create!(
        integration_installation: installation,
        integration_agent_source: installation.integration.agent_source,
        approver: current_user,
        approved_at: Time.current,
      )
    else
      installation.agent_consent&.destroy!
    end
  rescue ActiveRecord::ActiveRecordError => e
    Failbot.report!(e)
    false
  end
end
