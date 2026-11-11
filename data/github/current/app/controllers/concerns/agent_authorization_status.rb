# typed: true
# frozen_string_literal: true

module AgentAuthorizationStatus
  extend T::Helpers

  requires_ancestor { ApplicationController }

  private

  sig { returns(T::Boolean) }
  def authorization_status_field_enabled?
    FeatureFlag.vexi.enabled?(:copilot_swe_agent_authorization_status, current_user, default: false)
  end

  sig { params(integration_ids: T::Array[Integer]).returns(T::Set[Integer]) }
  def integration_ids_needing_authorization(integration_ids)
    AgenticApp::NeedsAuthorizationLookup.for_integration_ids(user: current_user, integration_ids: integration_ids)
  end
end
