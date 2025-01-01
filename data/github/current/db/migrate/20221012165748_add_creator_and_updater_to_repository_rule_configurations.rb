# typed: true
class AddCreatorAndUpdaterToRepositoryRuleConfigurations < ActiveRecord::Migration[7.1]
  self.use_connection_class(ApplicationRecord::Repositories)

  def change
    change_table :repository_rule_configurations, bulk: true do |t|
      t.column :created_by_id, :bigint, unsigned: true, null: true
      t.column :updated_by_id, :bigint, unsigned: true, null: true
    end
  end
end
