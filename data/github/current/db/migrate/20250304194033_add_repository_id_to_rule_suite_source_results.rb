# typed: true

class AddRepositoryIdToRuleSuiteSourceResults < ActiveRecord::Migration[8.1]
  self.use_connection_class(ApplicationRecord::Repositories)

  def change
    change_table :repository_rule_suite_source_results, bulk: true do |t|
      t.column :repository_id, :bigint, unsigned: true

      t.index [:repository_rule_suite_id, :source_id, :source_type, :repository_id], unique: true, name: "index_rule_suite_source_results_rule_suite_source_repo"
    end
  end
end
