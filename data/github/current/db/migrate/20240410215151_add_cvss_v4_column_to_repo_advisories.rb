class AddCvssV4ColumnToRepoAdvisories < ActiveRecord::Migration[7.2]
  self.use_connection_class(ApplicationRecord::Domain::RepositoriesCollab)

  def change
    change_table :repository_advisories, bulk: true do |t|
      t.column :cvss_v4, "varchar(255)", null: true
    end
  end
end
