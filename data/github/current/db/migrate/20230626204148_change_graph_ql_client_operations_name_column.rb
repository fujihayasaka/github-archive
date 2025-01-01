# typed: true
class ChangeGraphQlClientOperationsNameColumn < ActiveRecord::Migration[7.1]
  self.use_connection_class(ApplicationRecord::Domain::Api)
  def up
    change_column :graphql_client_operations, :alias, :string, limit: 256
  end

  def down
    change_column :graphql_client_operations, :alias, :string, limit: 40
  end
end
