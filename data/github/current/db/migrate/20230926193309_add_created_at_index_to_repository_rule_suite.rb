class AddCreatedAtIndexToRepositoryRuleSuite < ActiveRecord::Migration[7.1]
  self.use_connection_class(ApplicationRecord::Repositories)

  def change
    change_table :repository_rule_suites, bulk: true do |t|
      t.index :created_at
    end
  end
end
