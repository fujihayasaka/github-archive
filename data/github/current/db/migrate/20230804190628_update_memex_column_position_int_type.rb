# typed: true

class UpdateMemexColumnPositionIntType < ActiveRecord::Migration[7.1]
  self.use_connection_class(ApplicationRecord::Domain::Memexes)

  def up
    change_table :memex_project_columns, bulk: true do |t|
      t.change :position, :smallint, null: false
    end
  end

  def down
    change_table :memex_project_columns, bulk: true do |t|
      t.change :position, :tinyint, null: false
    end
  end
end
