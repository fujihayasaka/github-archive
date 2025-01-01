# typed: true
class CreateAuditLogDatadogSinkConfigurations < ActiveRecord::Migration[7.1]
  self.use_connection_class(ApplicationRecord::Collab)

  def change
    create_table :audit_log_datadog_sink_configurations, id: :bigint, unsigned: true, charset: "utf8mb4", collation: "utf8mb4_unicode_520_ci" do |t|
      t.column :encrypted_token, :string, limit: 1024
      t.column :site, "enum('US', 'US3', 'US5', 'EU1', 'US1-FED')", default: "US", null: false
      t.column :key_id, :string, limit: 1024
      t.datetime :created_at, precision: 6, null: false
      t.datetime :updated_at, precision: 6, null: false
    end
  end
end
