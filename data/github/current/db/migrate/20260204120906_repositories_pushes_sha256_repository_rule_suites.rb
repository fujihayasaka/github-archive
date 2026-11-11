# typed: true
# frozen_string_literal: true

class RepositoriesPushesSha256RepositoryRuleSuites < ActiveRecord::Migration[8.1]
  self.use_connection_class(ApplicationRecord::RepositoriesPushes)

  def up
    change_table :repository_rule_suites, bulk: true do |t|
      t.change :before_oid, :string, limit: 64, null: true
      t.change :after_oid, :string, limit: 64, null: true
      t.change :policy_oid, :string, limit: 64, null: true
    end
  end

  def down
    change_table :repository_rule_suites, bulk: true do |t|
      t.change :before_oid, :string, limit: 40, null: true
      t.change :after_oid, :string, limit: 40, null: true
      t.change :policy_oid, :string, limit: 40, null: true
    end
  end
end
