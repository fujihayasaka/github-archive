# typed: true
class AddBypassProhibitedToRepositoryRulesets < ActiveRecord::Migration[7.1]
  self.use_connection_class(ApplicationRecord::Repositories)

  def change
    add_column :repository_rulesets, :bypass_prohibited, :boolean, null: false, default: false
  end
end
