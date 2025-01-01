# typed: true
class CreateRuleRuns < ActiveRecord::Migration[7.1]
  self.use_connection_class(ApplicationRecord::Repositories)

  def change
    create_table :repository_rule_runs, id: :bigint, unsigned: true, charset: "utf8mb4", collation: "utf8mb4_unicode_520_ci" do |t|
      t.bigint :repository_rule_suite_id, unsigned: true, null: false
      t.string :rule_type, limit: 100, null: false
      t.string :rule_provider, limit: 100
      t.column :result, "tinyint(3)", unsigned: true, null: false, default: 0
      t.bigint :repository_rule_configuration_id, unsigned: true, null: true
      t.string :message, limit: 1024
      t.json :violations
      t.timestamps

      t.index [:repository_rule_configuration_id, :created_at], name: "index_repository_rule_runs_rule_config_id_created_at"
    end
  end

end
