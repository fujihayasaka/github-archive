class AddIdxAuditLogStreamConfigurations < ActiveRecord::Migration[7.2]
  self.use_connection_class(ApplicationRecord::Domain::UsersCollab)

  def change
    change_table(:audit_log_stream_configurations, bulk: true) do |t|
      t.column :idx, :integer, unsigned: true, null: false, default: 0
    end
  end
end
