# typed: true

class RemovingOldIndexFromRuleSuiteSourceResults < ActiveRecord::Migration[8.1]
  self.use_connection_class(ApplicationRecord::Repositories)

  def change
    change_table :repository_rule_suite_source_results, bulk: true do |t|
      t.remove_index column: [:repository_rule_suite_id, :source_id, :source_type], name: "index_repository_rule_suite_source_results_rule_suite_source"
    end
  end
end
