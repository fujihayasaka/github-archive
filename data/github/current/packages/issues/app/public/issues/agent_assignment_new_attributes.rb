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
  end
end
