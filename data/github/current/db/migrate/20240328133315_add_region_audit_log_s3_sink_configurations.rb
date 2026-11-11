class AddRegionAuditLogS3SinkConfigurations < ActiveRecord::Migration[7.2]
  self.use_connection_class(ApplicationRecord::Domain::UsersCollab)

  def change
    add_column :audit_log_s3_sink_configurations, :region, "varchar(36)", default: nil
  end
end
