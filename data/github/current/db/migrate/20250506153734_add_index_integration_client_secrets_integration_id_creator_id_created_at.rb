class AddIndexIntegrationClientSecretsIntegrationIdCreatorIdCreatedAt < ActiveRecord::Migration[8.1]
  self.use_connection_class(ApplicationRecord::Domain::Integrations)

  def change
    # This table has one or more existing columns that appears to be an integer primary or foreign key using a legacy data type.
    # We are in the process of upgrading all such columns to BIGINT UNSIGNED.
    # Even though you might not be changing anything about these columns we are asking developers to upgrade those columns when they author a migration that touches such tables.
    # Please migrate the following columns to BIGINT UNSIGNED in this migration.
    # For example within change_table :table_name, bulk: true do |t| include the line t.change :column_name, :bigint, unsigned: true: id, integration_id, creator_id
    change_table :integration_client_secrets, bulk: true do |t|
      t.change :id, :bigint, unsigned: true
      t.change :integration_id, :bigint, unsigned: true
      t.change :creator_id, :bigint, unsigned: true
    end

    add_index :integration_client_secrets, [:integration_id, :creator_id, :created_at], name: "index_integration_id_creator_id_created_at"
  end
end
