# typed: true

class AddBypassModeToRepositoryRulesetBypassActors < ActiveRecord::Migration[7.1]
  self.use_connection_class(ApplicationRecord::Repositories)

  def change
    add_column :repository_ruleset_bypass_actors, :bypass_mode, "tinyint(3)", unsigned: true, null: false, default: 0
  end
end
