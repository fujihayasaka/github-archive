# typed: true

class AddDescriptionToSearchShortcuts < ActiveRecord::Migration[7.1]
  self.use_connection_class(ApplicationRecord::Collab)

  def change
    add_column :search_shortcuts, :description, :mediumblob
  end
end
