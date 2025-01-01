# typed: true
class AddRulesetIdToRepositoryRuleConfigurations < ActiveRecord::Migration[7.1]
  self.use_connection_class(ApplicationRecord::Repositories)

  def change
    change_table :repository_rule_configurations, bulk: true do |t|
      t.column :repository_ruleset_id, :bigint, unsigned: true, null: true
      t.column :enforcement, "tinyint(3)", unsigned: true, null: false, default: 0
    end
  end
end
