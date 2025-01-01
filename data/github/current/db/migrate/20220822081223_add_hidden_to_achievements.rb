# typed: true
class AddHiddenToAchievements < ActiveRecord::Migration[7.1]
  self.use_connection_class(ApplicationRecord::Domain::Achievements)

  def change
    add_column :achievements, :hidden, :boolean, default: false, null: false
  end
end
