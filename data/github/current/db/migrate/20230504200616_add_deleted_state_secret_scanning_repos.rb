# typed: true

class AddDeletedStateSecretScanningRepos < ActiveRecord::Migration[7.1]
  self.use_connection_class(ApplicationRecord::Domain::TokenScanningService)
  def up
    change_table(:secret_scanning_repos, bulk: true) do |t|
      t.column :soft_delete_found_at, :datetime, precision: 6, null: true, comment: "if non-null, the timestamp for when token-scanning-service was notified the repository was soft-deleted."
      t.index [:soft_delete_found_at], unique: false, name: "secret_scanning_repos_soft_delete_found_at", comment: "support lookups for soft-deleted repos"
      t.index [:ghas_secret_scanning_enabled], unique: false, name: "secret_scanning_repos_ghas", comment: "support ghas-only lookups"
      t.index [:scannable], unique: false, name: "secret_scanning_repos_scannable", comment: "support scannable-only lookups"
    end
  end

  def down
    change_table(:secret_scanning_repos, bulk: true) do |t|
      t.remove :soft_delete_found_at
      t.remove_index name: "secret_scanning_repos_soft_delete_found_at"
      t.remove_index name: "secret_scanning_repos_ghas"
      t.remove_index name: "secret_scanning_repos_scannable"
    end
  end
end
