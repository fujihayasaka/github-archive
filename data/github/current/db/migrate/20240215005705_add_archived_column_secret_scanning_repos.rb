class AddArchivedColumnSecretScanningRepos < ActiveRecord::Migration[7.2]
  self.use_connection_class(ApplicationRecord::TokenScanningService)

  def change
    change_table :secret_scanning_repos, bulk: true do |t|
      t.boolean :archived, null: false, default: false, after: :visibility, comment: "the archived state of the repository"
    end
  end
end
