# typed: true
class AddPushTypeToPushes < ActiveRecord::Migration[7.1]
  self.use_connection_class(ApplicationRecord::RepositoriesPushes)

  def change
    add_column :pushes, :push_type, "tinyint(3)", unsigned: true, null: true
  end
end
