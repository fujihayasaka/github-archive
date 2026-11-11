# typed: true

class SecretScanningReposIdxChanges < ActiveRecord::Migration[8.1]
  self.use_connection_class(ApplicationRecord::TokenScanningService)

  def up
    change_table :secret_scanning_repos, bulk: true do |t|
      t.remove_index name: "secret_scanning_repos_ghas"
      t.index [:ghas_secret_scanning_enabled, :scannable, :soft_delete_found_at], unique: false, name: "secret_scanning_repos_ghas"

      t.remove_index name: "secret_scanning_repos_owner_id"
      t.remove_index name: "secret_scanning_repos_business_id"

      t.remove_index name: "secret_scanning_repos_scannable"
      t.index [:scannable, :results_visible], unique: false, name: "secret_scanning_repos_scannable"
    end
  end

  def down
    change_table :secret_scanning_repos, bulk: true do |t|
      t.remove_index name: "secret_scanning_repos_ghas"
      t.index [:ghas_secret_scanning_enabled], unique: false, name: "secret_scanning_repos_ghas"

      t.index [:owner_scope_id, :results_visible, :visibility, :business_id, :archived, :soft_delete_found_at], unique: false, name: "secret_scanning_repos_owner_id"
      t.index [:business_id, :results_visible, :visibility, :owner_scope_id, :archived, :soft_delete_found_at], unique: false, name: "secret_scanning_repos_business_id"

      t.remove_index name: "secret_scanning_repos_scannable"
      t.index [:scannable], unique: false, name: "secret_scanning_repos_scannable"
    end
  end
end
