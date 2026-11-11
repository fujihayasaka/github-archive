# typed: true

class AddCVESelectionToRepositoryAdvisories < ActiveRecord::Migration[8.2]
  self.use_connection_class(ApplicationRecord::Domain::RepositoriesCollab)

  def change
    change_table :repository_advisories, bulk: true do |t|
      t.column :cve_selection, "varchar(60)", null: true
    end
  end
end
