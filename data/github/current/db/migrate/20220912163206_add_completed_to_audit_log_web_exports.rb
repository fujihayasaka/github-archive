# typed: true
class AddCompletedToAuditLogWebExports < ActiveRecord::Migration[7.1]
  self.use_connection_class(ApplicationRecord::Collab)

  def change
    add_column :audit_log_web_exports, :completed, :boolean, null: false, default: false
  end
end
