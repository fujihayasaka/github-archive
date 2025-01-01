# typed: true
class DropRepositoriesPropertiesVersionColumn < ActiveRecord::Migration[7.1]
  self.use_connection_class(ApplicationRecord::Repositories)

  def change
    remove_column :repositories, :properties_version
  end
end
