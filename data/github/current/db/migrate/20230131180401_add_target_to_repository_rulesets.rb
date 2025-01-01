# typed: true

class AddTargetToRepositoryRulesets < ActiveRecord::Migration[7.1]
  self.use_connection_class(ApplicationRecord::Repositories)

  def change
    add_column :repository_rulesets, :target, "tinyint(3)", unsigned: true, null: false, default: 0
  end
end
