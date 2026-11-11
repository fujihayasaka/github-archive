# typed: true

class RemoveTruncatedFromAuditLogGitEventExport < ActiveRecord::Migration[8.1]
  self.use_connection_class(ApplicationRecord::Domain::UsersCollab)

  def up
    remove_column :audit_log_git_event_exports, :truncated, :tinyint
  end

  def down
    add_column :audit_log_git_event_exports, :truncated, :tinyint, default: 0, null: false
  end
end
