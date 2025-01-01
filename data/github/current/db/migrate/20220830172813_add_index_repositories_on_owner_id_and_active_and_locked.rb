# typed: true

# Being replaced by index_repositories_on_owner_id_active_locked_parent_id_public
# rubocop:disable GitHub/AvoidRedundantIndex
class AddIndexRepositoriesOnOwnerIdAndActiveAndLocked < ActiveRecord::Migration[7.1]
  self.use_connection_class(ApplicationRecord::Repositories)

  def change
    change_table :repositories, bulk: true do |t|
      t.index [:owner_id, :active, :locked]
    end
  end
end
