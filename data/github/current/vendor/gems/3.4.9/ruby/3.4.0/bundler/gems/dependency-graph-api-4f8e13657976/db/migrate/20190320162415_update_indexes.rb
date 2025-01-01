class UpdateIndexes < ActiveRecord::Migration[5.2]
  # Update the indexes to match production
  def change
    # The github_repository_id / public index should not be unique
    remove_index :dg_repositories, [:github_repository_id, :public]
    add_index :dg_repositories, [:github_repository_id, :public], unique: false

    # This index just doesn't exist
    add_index :dg_vulnerable_version_ranges, [:package_name, :encoded_lower_bound, :encoded_upper_bound], name: "index_dg_vuln_version_ranges_on_package_name_and_encoded_bounds"
  end
end
