# typed: true
# frozen_string_literal: true

module PullRequests
  module CopilotTimelineEventsHelper
    sig { params(issue_event: IssueEvent).returns(T::Boolean) }
    private def performed_by_code_review_agent?(issue_event)
      ccr_id = ::Apps::Privileged.integration(:copilot_pull_request_reviewer)&.id
      ccr_id.present? && issue_event.performed_by_integration_id == ccr_id
    end

    sig { params(issue_event: IssueEvent).returns(T::Boolean) }
    private def performed_by_coding_agent?(issue_event)
      if FeatureFlag.vexi.enabled?(:agentic_view_session, issue_event.actor_id, default: false)
        agent = ::AgenticApp.agent_for_integration_id(issue_event.performed_by_integration_id)
        return agent.present?
      end

      cca_id = ::Apps::Privileged.integration(:copilot_swe_agent)&.id
      cca_id.present? && issue_event.performed_by_integration_id == cca_id
    end
  end
end
