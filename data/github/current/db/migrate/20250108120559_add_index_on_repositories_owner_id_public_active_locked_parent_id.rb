# typed: true

# Replacing index_repositories_on_owner_id_and_active_and_locked
# rubocop:disable GitHub/AvoidRedundantIndex
class AddIndexOnRepositoriesOwnerIdPublicActiveLockedParentId < ActiveRecord::Migration[8.1]
  self.use_connection_class(ApplicationRecord::Repositories)

  def change
    add_index(
      :repositories,
      [:owner_id, :active, :locked, :parent_id, :public],
      name: "index_repositories_on_owner_id_active_locked_parent_id_public"
    )
  end
end
