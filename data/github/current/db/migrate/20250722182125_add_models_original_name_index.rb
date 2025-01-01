# typed: true

class AddModelsOriginalNameIndex < ActiveRecord::Migration[8.1]
  self.use_connection_class(ApplicationRecord::Domain::GitHubModels)

  def up
    add_index :models, :original_name
  end

  def down
    remove_index :models, :original_name
  end
end
