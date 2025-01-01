# typed: true
class AddGraphqlIndexEntriesTableAgain < ActiveRecord::Migration[7.1]
  self.use_connection_class(ApplicationRecord::Domain::Api)
  def change
    create_table :graphql_index_entries, primary_key: :id, id: :bigint, unsigned: true, charset: "utf8mb4", collation: "utf8mb4_unicode_520_ci" do |t|
      t.column :name, :string, null: false, limit: 40
    end
    add_index :graphql_index_entries, :name, unique: true
  end
end
