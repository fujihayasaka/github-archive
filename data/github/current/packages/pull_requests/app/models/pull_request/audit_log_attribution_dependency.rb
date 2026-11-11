# typed: true
# frozen_string_literal: true

module PullRequest::AuditLogAttributionDependency
  extend ActiveSupport::Concern
  extend T::Helpers

  requires_ancestor { PullRequest }

  # Public: Returns audit log fields for attribution if conditions are met
  #
  # This includes the user field that is used to show which human user
  # an agent was acting on behalf of in audit logs.
  #
  # agent_session_id - Optional String session ID to include in the audit log
  #
  # Returns Hash with user fields if attribution exists, empty Hash otherwise.
  sig { params(agent_session_id: T.nilable(String)).returns(T::Hash[Symbol, T.untyped]) }
  def audit_log_attribution_fields(agent_session_id: nil)
    {}.merge(audit_log_copilot_attribution_fields)
      .merge(audit_log_session_attribution_fields(agent_session_id))
  end

  # Public: Returns the user associated with the first copilot attribution
  #
  # Returns User if attribution exists, nil otherwise.
  sig { returns(T.nilable(User)) }
  def audit_log_copilot_attribution_user
    return nil if pull_request_copilot_attributions.empty?

    attribution = pull_request_copilot_attributions.first

    attribution&.user
  end

  private

  # Private: Returns copilot attribution fields for audit logging
  #
  # Returns Hash with user field if copilot attribution exists, empty Hash otherwise.
  sig { returns(T::Hash[Symbol, T.untyped]) }
  def audit_log_copilot_attribution_fields
    attribution_user = audit_log_copilot_attribution_user
    return {} unless attribution_user

    { user: attribution_user }
  end

  # Private: Returns session attribution fields for audit logging
  #
  # agent_session_id - Optional String session ID to include
  #
  # Returns Hash with agent_session_id if present, empty Hash otherwise.
  sig { params(agent_session_id: T.nilable(String)).returns(T::Hash[Symbol, T.untyped]) }
  def audit_log_session_attribution_fields(agent_session_id)
    return {} unless agent_session_id.present?

    { agent_session_id: agent_session_id }
  end
end
