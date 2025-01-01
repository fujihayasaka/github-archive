# typed: true

class CreateRuleSuites < ActiveRecord::Migration[7.1]
  self.use_connection_class(ApplicationRecord::Repositories)

  def change
    create_table :repository_rule_suites, id: :bigint, unsigned: true, charset: "utf8mb4", collation: "utf8mb4_unicode_520_ci" do |t|
      t.bigint :repository_id, unsigned: true, null: false
      t.column :ref_name, "varbinary(1024)", null: false
      t.string :before_oid, limit: 40
      t.string :after_oid, limit: 40
      t.string :policy_oid, limit: 40
      t.bigint :actor_id, unsigned: true
      t.string :actor_type, limit: 64
      t.column :result, "tinyint(3)", unsigned: true, null: false, default: 0
      t.timestamps

      t.index [:repository_id, :ref_name, :before_oid, :after_oid, :policy_oid], name: "index_repository_rulesets_ref_update"
      t.index [:repository_id, :created_at], name: "index_repository_rulesets_created_at"
    end
  end

end
