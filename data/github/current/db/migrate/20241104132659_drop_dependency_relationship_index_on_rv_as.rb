# typed: true

# rubocop:disable GitHub/EnsureDomainIsolationInMigration

class DropDependencyRelationshipIndexOnRvAs < ActiveRecord::Migration[8.0]
  self.use_connection_class(ApplicationRecord::Notify)

  def change
    change_table :repository_vulnerability_alerts, bulk: true do |t|
      t.remove_index :dependency_relationship, name: "index_rvas_on_dep_relationship"
    end
  end
end
