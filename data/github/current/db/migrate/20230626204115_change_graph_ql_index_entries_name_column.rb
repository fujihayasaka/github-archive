# typed: true

class ChangeGraphQlIndexEntriesNameColumn < ActiveRecord::Migration[7.1]
  self.use_connection_class(ApplicationRecord::Domain::Api)
  def up
    change_column :graphql_index_entries, :name, :string, limit: 256
  end

  def down
    change_column :graphql_index_entries, :name, :string, limit: 40
  end
end
