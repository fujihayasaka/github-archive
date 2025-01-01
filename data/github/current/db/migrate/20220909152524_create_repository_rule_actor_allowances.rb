# typed: true

class CreateRepositoryRuleActorAllowances < ActiveRecord::Migration[7.1]
  self.use_connection_class(ApplicationRecord::Repositories)

  def change
    create_table :repository_rule_actor_allowances, id: :bigint, unsigned: true, charset: "utf8mb4", collation: "utf8mb4_unicode_520_ci" do |t|
      t.bigint :repository_rule_configuration_id, unsigned: true, null: false
      t.column :actor_id, :bigint, unsigned: true, null: false
      t.column :actor_type, "varchar(40)", null: false
      t.string :action, limit: 100, null: true
      t.timestamps

      t.index [:repository_rule_configuration_id, :action], name: "index_repository_rule_actor_allowances_rule_config_action"
    end
  end
end
