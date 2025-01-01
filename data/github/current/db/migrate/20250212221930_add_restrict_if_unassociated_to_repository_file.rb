# typed: strict

class AddRestrictIfUnassociatedToRepositoryFile < ActiveRecord::Migration[8.1]
  self.use_connection_class(ApplicationRecord::Domain::AssetObjects)

  sig { void }
  def change
    add_column :repository_files, :restrict_if_unassociated, :boolean, null: true, default: nil
  end
end
