class AddRepositoryIdIndexToPackages < ActiveRecord::Migration[5.0]
  def change
    add_index :packages, :repository_id
  end
end
