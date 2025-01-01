# typed: true
class UpdateLastVisitedDefaultValue < ActiveRecord::Migration[7.1]
  self.use_connection_class(ApplicationRecord::Memex)

  def up
    change_column :memex_project_visits, :last_visited_at, :datetime, null: false, precision: 6, default: -> { "CURRENT_TIMESTAMP(6)" }
  end

  def down
    change_column :memex_project_visits, :last_visited_at, :datetime, null: false, precision: 6
  end
end
