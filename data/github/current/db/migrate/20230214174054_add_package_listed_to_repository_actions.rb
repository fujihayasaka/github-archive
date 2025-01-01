# typed: true

class AddPackageListedToRepositoryActions < ActiveRecord::Migration[7.1]
  self.use_connection_class(ApplicationRecord::Domain::Repositories)

  def change
    add_column :repository_actions, :package_listed, "tinyint(1)", null: false, default: 0
  end
end
