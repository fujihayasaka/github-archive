# typed: true
# frozen_string_literal: true

class AddRepositoryActorIndexToRuleSuites < ActiveRecord::Migration[8.1]
  self.use_connection_class(ApplicationRecord::Domain::Repositories)

  def change
    add_index :repository_rule_suites, [:repository_id, :actor_id, :actor_type], name: "index_repository_rule_suites_repository_actor"
  end
end
