# typed: true

class RuleConfigurationRemoveSourcePatternTarget < ActiveRecord::Migration[7.1]
  self.use_connection_class(ApplicationRecord::Repositories)

  def up
    change_table :repository_rule_configurations, bulk: true do |t|
      t.remove_index name: "index_repository_rule_configurations_source_and_target"
      t.remove :pattern
      t.remove :source_id
      t.remove :source_type
      t.remove :target
      t.remove :enforcement
    end
  end

  def down
    change_table :repository_rule_configurations, bulk: true do |t|
      t.column :pattern, "varbinary(1024)"
      t.bigint :source_id, unsigned: true
      t.string :source_type, limit: 100
      t.column :target, "tinyint(3)", unsigned: true
      t.column :enforcement, "tinyint(3)", unsigned: true, null: false, default: 0
      t.index [:source_id, :source_type, :target], name: "index_repository_rule_configurations_source_and_target"
    end
  end
end
