class AddValidityChecksEnabledIndexSecretScanningRepos < ActiveRecord::Migration[7.1]
  self.use_connection_class(ApplicationRecord::TokenScanningService)
  def up
    change_table :secret_scanning_repos, bulk: true do |t|
      t.index [:partner_validity_checks_enabled], name: "secret_scanning_repos_partner_validity_checks_enabled", comment: "supports looking up repos that have opted in to partner validity checks"
    end
  end

  def down
    change_table :secret_scanning_repos, bulk: true do |t|
      t.remove_index [:partner_validity_checks_enabled], name: "secret_scanning_repos_partner_validity_checks_enabled"

    end
  end
end
