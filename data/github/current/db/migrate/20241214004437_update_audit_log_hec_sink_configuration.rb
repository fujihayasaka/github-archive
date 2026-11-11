# typed: true

class UpdateAuditLogHecSinkConfiguration < ActiveRecord::Migration[8.1]
  self.use_connection_class(ApplicationRecord::Domain::UsersCollab)
  def change
    add_column :audit_log_hec_sink_configurations, :path, :string, default: "", null: false, limit: 1024
  end
end
