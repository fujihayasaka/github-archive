# typed: true
# frozen_string_literal: true

class AddBusinessIdToRuleSuites < ActiveRecord::Migration[8.0]
  self.use_connection_class(ApplicationRecord::Repositories)

  def change
    change_table :repository_rule_suites, bulk: true do |t|
      t.column :business_id, :bigint, unsigned: true, null: true
      t.index [:business_id, :created_at], name: "index_repository_rule_suites_business_id_created_at"
      t.index [:business_id, :actor_id, :actor_type], unique: false, name: "index_repository_rule_suites_business_actor"
    end
  end
end
