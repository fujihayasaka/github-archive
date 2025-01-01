# typed: true

class UpdateMemexFilterLength < ActiveRecord::Migration[8.1]
  self.use_connection_class(ApplicationRecord::Domain::Memexes)

  def up
    change_table :memex_project_views, bulk: true do |t|
      t.change :filter, "varchar(512)", null: true
    end
  end

  def down
    change_table :memex_project_views, bulk: true do |t|
      t.change :filter, "varchar(256)", null: true
    end
  end
end
