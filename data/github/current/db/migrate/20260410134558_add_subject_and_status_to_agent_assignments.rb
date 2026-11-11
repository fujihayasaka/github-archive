# typed: true

class AddSubjectAndStatusToAgentAssignments < ActiveRecord::Migration[8.2]
  self.use_connection_class(ApplicationRecord::Domain::IssuesPullRequests)

  def change
    change_table :agent_assignments, bulk: true do |t|
      t.column :subject_type, :tinyint, unsigned: true, null: true,
        comment: "Type of entity being worked on (e.g. issue). Nullable during backfill."
      t.column :subject_id, :bigint, unsigned: true, null: true,
        comment: "Reference to the entity being worked on (e.g. issue_id). Nullable during backfill."
      t.column :status, :tinyint, unsigned: true, null: true,
        comment: "Lifecycle status of the assignment (e.g. pending, active, completed, failed)"

      t.index [:subject_id, :subject_type],
        name: "index_agent_assignments_on_subject_id_and_subject_type"
    end
  end
end
