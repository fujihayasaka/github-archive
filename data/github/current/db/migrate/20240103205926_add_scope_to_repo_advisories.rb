# typed: true

class AddScopeToRepoAdvisories < ActiveRecord::Migration[7.2]
  self.use_connection_class(ApplicationRecord::Domain::RepositoriesCollab)
  def change
    add_column :repository_advisories, :repo_advisory_type, :tinyint, null: true
  end
end
