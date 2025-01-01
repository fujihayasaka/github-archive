class AddExpiredToAuditLogWebExport < ActiveRecord::Migration[7.2]
  self.use_connection_class(ApplicationRecord::Domain::UsersCollab)

  def up
    change_table(:audit_log_web_exports, bulk: true) do |t|
      t.column :expired, :boolean, default: false, null: false, comment: "Has the export expired"
    end
  end

  def down
    change_table(:audit_log_web_exports, bulk: true) do |t|
      t.remove :expired
    end
  end
end
