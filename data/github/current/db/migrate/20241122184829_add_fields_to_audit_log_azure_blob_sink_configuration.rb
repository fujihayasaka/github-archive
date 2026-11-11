# typed: true

class AddFieldsToAuditLogAzureBlobSinkConfiguration < ActiveRecord::Migration[8.0]
  self.use_connection_class(ApplicationRecord::Domain::UsersCollab)

  def up
    change_table(:audit_log_azure_blob_sink_configurations, bulk: true) do |t|
      t.column :authentication_type, "enum('access_keys', 'oidc_auditlog', 'oidc_github')", default: "access_keys", null: false
      t.column :client_id, :string, limit: 36
      t.column :tenant_id, :string, limit: 36
      t.column :storage_account_name, :string, limit: 24
    end
  end

  def down
    change_table(:audit_log_azure_blob_sink_configurations, bulk: true) do |t|
      t.remove :authentication_type
      t.remove :client_id
      t.remove :tenant_id
      t.remove :storage_account_name
    end
  end
end
