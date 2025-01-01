# typed: true

class AddRulesetAndHistoryIdToRuleRun < ActiveRecord::Migration[7.1]
  self.use_connection_class(ApplicationRecord::Repositories)

  def change
    change_table :repository_rule_runs, bulk: true do |t|
      t.column :rule_provider_id, :bigint, unsigned: true, null: true
      t.column :rule_history_id, :bigint, unsigned: true, null: true

      t.remove_index [:repository_rule_suite_id], name: "index_rule_runs_rule_suite_id"
      t.index [:repository_rule_suite_id, :rule_provider_id, :rule_provider], name: "index_rule_runs_on_rule_suite_and_provider"
    end
  end
end
