class AddIndexToSecretScanningReposForBusinessLevelQueries < ActiveRecord::Migration[7.2]
  self.use_connection_class(ApplicationRecord::TokenScanningService)

  def change
    change_table :secret_scanning_repos, bulk: true do |t|
      t.index [:business_id, :soft_delete_found_at], name: "secret_scanning_repos_business_id_soft_delete_found_at", comment: "index for finding all repos under a business"
    end
  end
end
