# typed: true

class DropGraphqlIndexReferences < ActiveRecord::Migration[7.1]
  def change
    drop_table :graphql_index_references, if_exists: true
  end
end
