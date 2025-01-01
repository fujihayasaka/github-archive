class SecretScanningReposSlice < ActiveRecord::Migration[7.2]
  self.use_connection_class(ApplicationRecord::TokenScanningService)
  def up
    change_table(:secret_scanning_repos, bulk: true) do |t|
      # support static slicing of repos so we can dispatch concurrent queries
      t.column :slice10, "TINYINT UNSIGNED GENERATED ALWAYS AS ((floor(`created_at`) % 10)) VIRTUAL NOT NULL"
      t.index [:owner_scope_id, :results_visible, :slice10, :visibility, :business_id, :archived, :soft_delete_found_at], name: "secret_scanning_repos_owner_sliced"
      t.index [:business_id, :results_visible, :slice10, :visibility, :owner_scope_id, :archived, :soft_delete_found_at], name: "secret_scanning_repos_business_sliced"

      # added soft delete to existing secret_scanning_repos_business_id index, so this is now redundant
      t.remove_index name: "secret_scanning_repos_business_id_soft_delete_found_at"

      # add covering values when filtering by owner_scope_id
      t.remove_index name: "secret_scanning_repos_owner_id"
      t.index [:owner_scope_id, :results_visible, :visibility, :business_id, :archived, :soft_delete_found_at], name: "secret_scanning_repos_owner_id"

      # add covering values when filtering by business_id
      t.remove_index name: "secret_scanning_repos_business_id"
      t.index [:business_id, :results_visible, :visibility, :owner_scope_id, :archived, :soft_delete_found_at], name: "secret_scanning_repos_business_id"
    end
  end

  def down
    change_table(:secret_scanning_repos, bulk: true) do |t|
      t.remove :slice10
      t.remove_index name: "secret_scanning_repos_owner_sliced"
      t.remove_index name: "secret_scanning_repos_business_sliced"

      t.index [:business_id, :soft_delete_found_at], name: "secret_scanning_repos_business_id_soft_delete_found_at", comment: "index for finding all repos under a business"

      t.remove_index name: "secret_scanning_repos_owner_id"
      t.index [:owner_scope_id, :results_visible, :visibility], name: "secret_scanning_repos_owner_id", comment: "index for finding all visible repos under a provided owner scope ID"

      t.remove_index name: "secret_scanning_repos_business_id"
      t.index [:business_id, :results_visible, :visibility], name: "secret_scanning_repos_business_id", comment: "index for finding all visible repos under a business"
    end
  end

end
