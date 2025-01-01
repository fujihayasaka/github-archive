# typed: true

class AddGraphqlClientOperationsTableAgain < ActiveRecord::Migration[7.1]
  self.use_connection_class(ApplicationRecord::Domain::Api)
  def change
    create_table :graphql_client_operations, primary_key: :id, id: :bigint, unsigned: true, charset: "utf8mb4", collation: "utf8mb4_unicode_520_ci" do |t|
      t.references :graphql_client, null: false, index: false
      t.references :graphql_operation, null: false
      t.column :alias, :string, null: false, limit: 40
      t.column :last_used_at, :datetime, precision: 6
      t.column :is_archived, :boolean, null: false, default: false
      t.timestamps
    end
    add_index :graphql_client_operations, [:graphql_client_id, :alias], unique: true, name: "graphql_client_operations_pairs"
    add_index :graphql_client_operations, :is_archived
  end
end
