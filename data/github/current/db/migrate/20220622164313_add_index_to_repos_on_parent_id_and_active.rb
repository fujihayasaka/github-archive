# typed: true

class AddIndexToReposOnParentIdAndActive < ActiveRecord::Migration[7.1]
  self.use_connection_class(ApplicationRecord::Repositories)

  def change
    change_table :repositories, bulk: true do |t|
      t.remove_index [:parent_id], name: "index_repositories_on_parent_id"
      t.index [:parent_id, :active], name: "index_repositories_on_parent_id_and_active"
    end
  end
end
