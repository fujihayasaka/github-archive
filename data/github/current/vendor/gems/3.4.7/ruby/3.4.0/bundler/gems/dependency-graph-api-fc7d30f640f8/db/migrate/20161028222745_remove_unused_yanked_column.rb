class RemoveUnusedYankedColumn < ActiveRecord::Migration[5.0]
  def change
    remove_column :package_versions, :yanked, :boolean
  end
end
