# typed: true
class AddGraphqlIndexReferencesTable < ActiveRecord::Migration[7.1]
  def change
    create_table :graphql_index_references, primary_key: :id, id: :bigint, unsigned: true, charset: "utf8mb4", collation: "utf8mb4_unicode_520_ci" do |t|
      t.references :graphql_index_entry, null: false, index: false
      t.references :graphql_operation, null: false
    end
    add_index :graphql_index_references, [:graphql_index_entry_id, :graphql_operation_id], unique: true, name: "graphql_index_reference_pairs"
  end
end
