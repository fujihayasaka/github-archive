class AddTotalChunksToAuditLogGitEventExport < ActiveRecord::Migration[7.2]
  self.use_connection_class(ApplicationRecord::Domain::UsersCollab)

  def up
    change_table(:audit_log_git_event_exports, bulk: true) do |t|
      t.column :total_chunks, :integer, unsigned: true, default: 0, comment: "Total number of chunks in git export"
    end
  end

  def down
    change_table(:audit_log_git_event_exports, bulk: true) do |t|
      t.remove :total_chunks
    end
  end
end
