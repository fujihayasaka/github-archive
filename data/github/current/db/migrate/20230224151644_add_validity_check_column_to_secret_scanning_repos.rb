# typed: true

class AddValidityCheckColumnToSecretScanningRepos < ActiveRecord::Migration[7.1]
  self.use_connection_class(ApplicationRecord::Domain::TokenScanningService)
  def up
    change_table(:secret_scanning_repos, bulk: true) do |t|
      t.column :partner_validity_checks_enabled, :boolean, null: false, default: false, comment: "whether validity checks for partners tokens are enabled for this repository"
    end
  end

  def down
    change_table(:secret_scanning_repos, bulk: true) do |t|
      t.remove :partner_validity_checks_enabled
    end
  end
end
