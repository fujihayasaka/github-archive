class CreateAuditLogHecSinkConfiguration < ActiveRecord::Migration[8.0]
  self.use_connection_class(ApplicationRecord::Domain::UsersCollab)
  def change
    create_table :audit_log_hec_sink_configurations, id: :bigint, unsigned: true, charset: "utf8mb4", collation: "utf8mb4_unicode_520_ci" do |t|
      t.column :domain, :string, limit: 1024
      t.column :port, :int, limit: 1024
      t.column :key_id, :string, limit: 1024
      t.column :encrypted_token, :string, limit: 1024
      t.column :ssl_verify, :tinyint, limit: 1
      t.datetime :created_at, precision: 6, null: false
      t.datetime :updated_at, precision: 6, null: false
    end
  end
end
