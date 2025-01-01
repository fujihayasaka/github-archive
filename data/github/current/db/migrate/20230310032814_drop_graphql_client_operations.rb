# typed: true
class DropGraphqlClientOperations < ActiveRecord::Migration[7.1]
  def change
    drop_table :graphql_client_operations, if_exists: true
  end
end
