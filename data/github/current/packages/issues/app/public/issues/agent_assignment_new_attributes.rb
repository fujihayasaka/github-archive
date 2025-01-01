# typed: strict
# frozen_string_literal: true

module Issues
  # Used to create new agent assignments
  class AgentAssignmentNewAttributes < T::Struct
    prop :issue_ids, T::Array[Integer]
    prop :repo_name_with_owner, String
    prop :base_ref, String
    prop :custom_instructions, T.nilable(String)
  end
end
