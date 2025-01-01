# typed: true
class ModifyBypassProhibitedRepositoryRulesets < ActiveRecord::Migration[7.1]
  self.use_connection_class(ApplicationRecord::Repositories)

  def up
    change_column :repository_rulesets, :bypass_prohibited, "tinyint(3)", unsigned: true, null: false, default: 0
  end

  def down
    change_column :repository_rulesets, :bypass_prohibited, :boolean, null: false, default: false
  end
end
