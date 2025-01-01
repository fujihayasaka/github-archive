# typed: true
class DropGraphqlIndexEntries < ActiveRecord::Migration[7.1]
  def change
    drop_table :graphql_index_entries, if_exists: true
  end
end
