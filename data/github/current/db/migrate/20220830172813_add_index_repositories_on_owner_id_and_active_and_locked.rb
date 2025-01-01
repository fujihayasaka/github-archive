# typed: true
class AddIndexRepositoriesOnOwnerIdAndActiveAndLocked < ActiveRecord::Migration[7.1]
  self.use_connection_class(ApplicationRecord::Repositories)

  def change
    change_table :repositories, bulk: true do |t|
      t.index [:owner_id, :active, :locked]
    end
  end
end
