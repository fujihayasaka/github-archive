# typed: true
# frozen_string_literal: true

class UpdateRepositoryRuleSuitesIndexNames < ActiveRecord::Migration[7.1]
  self.use_connection_class(ApplicationRecord::Repositories)

  def change
    rename_index :repository_rule_suites, "index_repository_rulesets_ref_update", "index_repository_rule_suites_ref_update"
    rename_index :repository_rule_suites, "index_repository_rulesets_created_at", "index_repository_rule_suites_created_at"
  end
end
