# typed: true
# frozen_string_literal: true

module AgenticAppConflictCheck
  extend ActiveSupport::Concern

  private

  sig { params(agent: AgenticApp, target: T.any(User, Organization)).returns(T::Boolean) }
  def target_has_conflicting_app_installed?(agent, target)
    conflicting_app_ids = Apps::Privileged.property(:conflicting_client_ids, app: agent.integration)
    return false if conflicting_app_ids.blank?

    # First query: integrations table (users_domain) — fetch IDs by key
    conflicting_integration_ids = Integration.where(key: conflicting_app_ids).pluck(:id)
    return false if conflicting_integration_ids.empty?

    # Second query: integration_installations table (authnz_domain) — no cross-cluster JOIN
    IntegrationInstallation
      .with_target(target)
      .where(integration_id: conflicting_integration_ids)
      .exists?
  end
end
