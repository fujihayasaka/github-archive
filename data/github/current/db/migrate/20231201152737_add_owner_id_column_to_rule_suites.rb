# typed: true

class AddOwnerIdColumnToRuleSuites < ActiveRecord::Migration[7.2]
  # rubocop:todo GitHub/EnsureDomainIsolationInMigration (can be dropped once table move completed)
  self.use_connection_class(ApplicationRecord::Repositories)

  def change
    change_table :repository_rule_suites, bulk: true do |t|
      t.column :owner_id, :bigint, unsigned: true, null: true
      t.index [:owner_id, :created_at], name: "index_repository_rule_suites_owner_id_created_at"
    end
  end
end
