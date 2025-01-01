# typed: true
class DropGraphqlClients < ActiveRecord::Migration[7.1]
  def change
    drop_table :graphql_clients, if_exists: true
  end
end
