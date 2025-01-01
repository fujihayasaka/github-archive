# typed: true

class EnforceNotNullOnRepositoryIdForRuleSuiteSourceResults < ActiveRecord::Migration[8.1]
  self.use_connection_class(ApplicationRecord::Repositories)

  def change
    change_column_null :repository_rule_suite_source_results, :repository_id, false
  end
end
