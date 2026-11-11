# typed: true

class AddLinkedResourcesToUsageRecords < ActiveRecord::Migration[8.1]
  self.use_connection_class(ApplicationRecord::Domain::Codespaces)

  def change
    add_column :codespace_usage_records, :linked_resources, :json, null: true
  end
end
