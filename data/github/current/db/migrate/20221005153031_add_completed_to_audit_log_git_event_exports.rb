# typed: true

class AddCompletedToAuditLogGitEventExports < ActiveRecord::Migration[7.1]
  self.use_connection_class(ApplicationRecord::Collab)

  def up
    change_table(:audit_log_git_event_exports, bulk: true) do |t|
      t.column :completed, :boolean, null: false, default: false
      t.change :id, :bigint, unsigned: true
      t.change :actor_id, :bigint, unsigned: true
      t.change :subject_id, :bigint, unsigned: true
    end
  end

  def down
    change_table(:audit_log_git_event_exports, bulk: true) do |t|
      t.remove :completed
      t.change :id, :integer
      t.change :actor_id, :integer
      t.change :subject_id, :integer
    end
  end
end
