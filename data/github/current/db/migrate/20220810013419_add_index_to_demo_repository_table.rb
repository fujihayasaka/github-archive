# typed: true
class AddIndexToDemoRepositoryTable < ActiveRecord::Migration[7.1]
  self.use_connection_class(ApplicationRecord::Domain::Repositories)

  def change
    add_index :demo_repositories, :repository_id, unique: true
  end
end
