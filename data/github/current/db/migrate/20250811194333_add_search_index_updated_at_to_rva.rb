# typed: true
# frozen_string_literal: true

class AddSearchIndexUpdatedAtToRva < ActiveRecord::Migration[8.1]
  self.use_connection_class(ApplicationRecord::Domain::RepositoriesNotify)

  def change
    change_table :repository_vulnerability_alerts, bulk: true do |t|
      t.column :search_index_updated_at, :datetime, precision: 6, null: true, comment: "Timestamp of the last update to the search index for this alert"
    end

    add_index :repository_vulnerability_alerts, :search_index_updated_at, name: "index_rva_on_search_index_updated_at"
  end
end
