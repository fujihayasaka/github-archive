# typed: true

class AddTargetRepositoryIdToAgentAssignments < ActiveRecord::Migration[8.2]
  self.use_connection_class(ApplicationRecord::Domain::IssuesPullRequests)

  def change
    change_table :agent_assignments, bulk: true do |t|
      t.column :target_repository_id, :bigint, unsigned: true, null: true,
        comment: "Repository where the agent works (may differ from repository_id when cross-repo)"
      t.column :target_owner_id, :bigint, unsigned: true, null: true,
        comment: "Owner of the target repository (may differ from the source repository owner)"

      t.index [:task_id, :target_repository_id],
        name: "index_agent_assignments_on_task_id_and_target_repository_id"
    end
  end
end
