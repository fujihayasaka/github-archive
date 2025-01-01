# typed: true
# frozen_string_literal: true

class AddActorIndexToRuleSuites < ActiveRecord::Migration[7.2]
  self.use_connection_class(ApplicationRecord::Repositories)

  def change
    add_index :repository_rule_suites, [:owner_id, :actor_id, :actor_type], unique: false, name: "index_repository_rule_suites_owner_actor"
  end
end
