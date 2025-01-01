class AddTruncatedToAuditLogWebExport < ActiveRecord::Migration[7.2]
  self.use_connection_class(ApplicationRecord::Domain::UsersCollab)

  def up
    change_table(:audit_log_web_exports, bulk: true) do |t|
      t.column :truncated, :boolean, default: false, null: false, comment: "Has the export been truncated"
    end
  end

  def down
    change_table(:audit_log_web_exports, bulk: true) do |t|
      t.remove :truncated
    end
  end
end
