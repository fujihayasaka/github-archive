class AddRepoIdToPackages < ActiveRecord::Migration[5.0]
  def change
    add_column :packages, :repository_id, :integer, index: true
  end
end
