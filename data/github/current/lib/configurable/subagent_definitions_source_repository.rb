# typed: strict
# frozen_string_literal: true

module Configurable
  module SubagentDefinitionsSourceRepository
    extend T::Helpers

    requires_ancestor { Configurable }

    KEY = T.let("subagent_definitions_source_repo_id", String)

    SOURCE_REPO_NAME = T.let(".github-private", String)

    sig { params(actor: User, repo_id: T.nilable(Integer)).void }
    def set_subagent_definitions_source_repository_id(actor:, repo_id:)
      return if repo_id.nil?

      old_repo_id = subagent_definitions_source_repository_id
      config.set!(KEY, repo_id.to_s, actor)

      T.unsafe(self).instrument :custom_agent_source_update, {
        actor: actor,
        action: "copilot.custom_agent_source_update",
        old_value: old_repo_id,
        new_value: repo_id,
        business_id: T.unsafe(self).id,
        prefix: :copilot
      }
    end

    sig { params(actor: User).void }
    def unset_subagent_definitions_source_repository_id(actor:)
      old_value = subagent_definitions_source_repository_id
      config.delete(KEY, actor)
      T.unsafe(self).instrument :custom_agent_source_update, {
        actor: actor,
        action: "copilot.custom_agent_source_update",
        old_value: old_value,
        new_value: nil,
        business_id: T.unsafe(self).id,
        prefix: :copilot
      }
    end

    sig { returns(T.nilable(Integer)) }
    def subagent_definitions_source_repository_id
      config.int(KEY)
    end
  end
end
