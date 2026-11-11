# typed: strict
# frozen_string_literal: true

module Issues
  # Used to create new agent assignments
  class AgentAssignmentNewAttributes < T::Struct
    prop :target_repository, Repository
    prop :base_ref, T.nilable(String)
    prop :custom_instructions, T.nilable(String)
    prop :custom_agent, T.nilable(String), default: nil
    prop :agent_id, T.nilable(Integer), default: nil
    prop :remote_ip, T.nilable(String), default: nil
    prop :model, T.nilable(String), default: nil
    prop :skip_pull_request, T.nilable(T::Boolean), default: false
    prop :agent_assignment_ids, T::Hash[String, Integer], default: {}
    # When nil, the assignment is sourced from the issue itself (source_type: :issue, source_id: issue.id).
    # Callers that originate from a different system — e.g. Memex auto-assign workflows — must set these to
    # meet CCA auditing requirements. They are nilable rather than required because this struct is shared
    # across N issues in bulk assignment paths, so the per-issue source_id cannot be baked in at construction
    # time; the issue-default is resolved per-iteration inside Issues::Domain::Copilot#create_agent_assignment_record.
    # Allowed values mirror AgentAssignment.source_types keys (:issue, :workflow_action).
    prop :source_type, T.nilable(Symbol), default: nil
    prop :source_id, T.nilable(Integer), default: nil

    sig { returns(T.nilable(User)) }
    def resolve_bot
      bot = if agent_id
        agent = AgenticApp.agent_for_integration_id(agent_id)
        agent&.integration&.bot
      end
      bot || Apps::Privileged.integration(:copilot_swe_agent)&.bot
    end
  end
end
