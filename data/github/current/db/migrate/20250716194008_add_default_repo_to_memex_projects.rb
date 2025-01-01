# typed: true

class AddDefaultRepoToMemexProjects < ActiveRecord::Migration[8.1]
  self.use_connection_class(ApplicationRecord::Domain::Memexes)

  def change
    add_column :memex_projects, :default_issue_create_target_repository_id, :bigint, unsigned: true
  end
end
