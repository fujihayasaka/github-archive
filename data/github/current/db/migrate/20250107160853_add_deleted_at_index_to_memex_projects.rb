# typed: true

class AddDeletedAtIndexToMemexProjects < ActiveRecord::Migration[8.1]
  self.use_connection_class(ApplicationRecord::Domain::Memexes)

  def up
    change_table(:memex_projects, bulk: true) do |t|
      t.index [:deleted_at], name: "index_memex_projects_on_deleted", comment: "for looking up deleted projects"
    end
  end

  def down
    change_table(:memex_projects, bulk: true) do |t|
      t.remove_index name: "index_memex_projects_on_deleted"
    end
  end
end
