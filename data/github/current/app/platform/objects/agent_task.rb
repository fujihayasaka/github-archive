# typed: strict
# frozen_string_literal: true

module Platform
  module Objects
    class AgentTask < Objects::Base
      docs_category :copilot
      COHORT = "2025-01-01"

      description "An agent task within a project."

      model_name "MemexAgentTask"

      visibility :internal

      implements_node templates: [
        [:mat, :owner_id, :agent_task_id]
      ],
      as: "MAT",
      ready_date: COHORT do |agent_task|
        {
          prefix: :mat,
          owner_id: agent_task.owner_id,
          agent_task_id: agent_task.id,
        }
      end

      sig { params(permission: T.untyped, object: T.untyped).returns(T.untyped) }
      def self.async_api_can_access?(permission, object)
        object.async_memex_project_items.then do |items|
          item = items.first
          next false unless item

          permission.typed_can_access?("ProjectV2Item", item)
        end
      end

      sig { params(permission: T.untyped, object: T.untyped).returns(T.untyped) }
      def self.async_viewer_can_see?(permission, object)
        object.async_memex_project_items.then do |items|
          item = items.first
          next false unless item

          permission.typed_can_see?("ProjectV2Item", item)
        end
      end

      minimum_accepted_scopes ["read:org", "repo", "read:project"]

      created_at_field

      updated_at_field
    end
  end
end
