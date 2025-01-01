class AddWikiScanningToSecretScanningRepos < ActiveRecord::Migration[7.2]
  self.use_connection_class(ApplicationRecord::TokenScanningService)
  def change
    change_table :secret_scanning_repos, bulk: true do |t|
      t.boolean :wiki_scanning, null: false, default: false, comment: "whether wiki exists and can be scanned for this repository"
    end
  end
end
