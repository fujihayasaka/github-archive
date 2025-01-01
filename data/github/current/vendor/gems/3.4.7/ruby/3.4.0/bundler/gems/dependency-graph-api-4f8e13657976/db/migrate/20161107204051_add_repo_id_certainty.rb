class AddRepoIdCertainty < ActiveRecord::Migration[5.0]
  def change
    add_column :packages, :repository_id_certainty, :integer, default: 0, null: false
    add_column :package_versions, :repository_id_certainty, :integer, default: 0, null: false
  end
end
