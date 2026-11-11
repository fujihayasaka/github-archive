class AddLastVisitedOnToMemexProjects < ActiveRecord::Migration[7.2]
  self.use_connection_class(ApplicationRecord::Domain::Memexes)

  def change
    change_table :memex_projects, bulk: true do |t|
      t.date :last_visited_on, index: true
    end
  end
end
