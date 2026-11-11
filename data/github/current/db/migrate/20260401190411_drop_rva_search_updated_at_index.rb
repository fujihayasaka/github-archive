# typed: true
# frozen_string_literal: true

class DropRvaSearchUpdatedAtIndex < ActiveRecord::Migration[8.2]
  self.use_connection_class(ApplicationRecord::Domain::RepositoriesNotify)

  def up
    remove_index :repository_vulnerability_alerts, :search_index_updated_at, name: "index_rva_on_search_index_updated_at", if_exists: true
  end

  def down
    add_index :repository_vulnerability_alerts, :search_index_updated_at, name: "index_rva_on_search_index_updated_at", if_not_exists: true
  end
end
