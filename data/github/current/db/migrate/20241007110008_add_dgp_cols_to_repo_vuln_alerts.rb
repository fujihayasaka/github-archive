# typed: true

# rubocop:disable GitHub/EnsureDomainIsolationInMigration

class AddDgpColsToRepoVulnAlerts < ActiveRecord::Migration[8.0]
  self.use_connection_class(ApplicationRecord::Notify)

  def change
    change_table :repository_vulnerability_alerts, bulk: true do |t|
      t.integer :dependency_relationship, default: 0, limit: 1
      t.bigint :dgp_dependency_id, unsigned: true, null: true

      t.index :dependency_relationship, name: "index_rvas_on_dep_relationship"
    end
  end
end
