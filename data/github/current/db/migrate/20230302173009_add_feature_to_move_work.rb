# typed: true

class AddFeatureToMoveWork < ActiveRecord::Migration[7.1]
  self.use_connection_class(ApplicationRecord::Domain::RepositoriesCollab)

  def change
    add_column :move_works, :feature, "tinyint unsigned", null: true, comment: "enum representing the feature move work was initiated from"
  end
end
