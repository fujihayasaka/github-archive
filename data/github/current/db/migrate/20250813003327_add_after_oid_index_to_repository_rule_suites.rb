# typed: true
# frozen_string_literal: true

class AddAfterOidIndexToRepositoryRuleSuites < ActiveRecord::Migration[8.1]
  self.use_connection_class(ApplicationRecord::RepositoriesPushes)

  def change
    add_index :repository_rule_suites, [:repository_id, :after_oid], name: :index_repository_rule_suites_after_oid
  end
end
