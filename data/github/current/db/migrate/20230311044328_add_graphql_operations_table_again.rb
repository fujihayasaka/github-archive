# typed: true
class AddGraphqlOperationsTableAgain < ActiveRecord::Migration[7.1]
  self.use_connection_class(ApplicationRecord::Domain::Api)
  def change
    create_table :graphql_operations, primary_key: :id, id: :bigint, unsigned: true, charset: "utf8mb4", collation: "utf8mb4_unicode_520_ci" do |t|
      t.column :digest, :string, null: false, limit: 64
      t.column :body, :text, null: false
      t.column :name, :string, null: false, limit: 40
      t.timestamps
    end
    add_index :graphql_operations, :digest, unique: true
  end
end
