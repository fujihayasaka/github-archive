# typed: true

class DropGraphqlOperations < ActiveRecord::Migration[7.1]
  def change
    drop_table :graphql_operations, if_exists: true
  end
end
