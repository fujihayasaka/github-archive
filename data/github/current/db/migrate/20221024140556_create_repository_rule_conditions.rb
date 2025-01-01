# typed: true
class CreateRepositoryRuleConditions < ActiveRecord::Migration[7.1]
  self.use_connection_class(ApplicationRecord::Repositories)

  def change
    create_table :repository_rule_conditions, id: :bigint, unsigned: true, charset: "utf8mb4", collation: "utf8mb4_unicode_520_ci" do |t|
      t.json :parameters, null: false
      t.column :target, "tinyint(3)", unsigned: true, null: false
      t.string :condition_type, limit: 100, null: false
      t.bigint :repository_ruleset_id, unsigned: true
      t.timestamps

      t.index  :repository_ruleset_id, name: "index_repository_rule_conditions_on_repository_ruleset_id"
    end
  end
end
