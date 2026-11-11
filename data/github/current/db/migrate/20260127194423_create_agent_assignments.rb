# typed: true

class CreateAgentAssignments < ActiveRecord::Migration[8.2]
  self.use_connection_class(ApplicationRecord::Domain::IssuesPullRequests)

  def change
    create_table :agent_assignments, id: :bigint, unsigned: true, charset: "utf8mb4", collation: "utf8mb4_unicode_520_ci" do |t|
      t.bigint :repository_id, unsigned: true, null: false
      t.column :source_type, :tinyint, unsigned: true, null: false, comment: "Type of source generating this assignment"
      t.bigint :source_id, unsigned: true, null: false, comment: "Reference to the source entity (e.g. issue_id)"
      t.bigint :assigner_id, unsigned: true, null: false, comment: "Reference to user who created the assignment"
      t.bigint :assignee_id, unsigned: true, null: false, comment: "Reference to the agent being assigned"
      t.string :task_id, limit: 36, null: true, comment: "Unique task identifier (UUID) managed by copilot service(s)"

      t.timestamps null: false

      t.index [:source_id, :source_type], name: "index_agent_assignments_on_source_id_and_source_type"
      t.index [:task_id, :repository_id], unique: true, name: "index_agent_assignments_on_task_id"
    end

    add_vindex :agent_assignments, :hash, :repository_id

    add_auto_increment :agent_assignments, :id, :agent_assignments_id_seq
  end
end
