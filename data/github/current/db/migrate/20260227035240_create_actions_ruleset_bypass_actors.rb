# typed: true
# frozen_string_literal: true

class CreateActionsRulesetBypassActors < ActiveRecord::Migration[8.2]
  self.use_connection_class(ApplicationRecord::ActionsEnvironments)

  def change
    create_table :actions_ruleset_bypass_actors, id: :bigint, unsigned: true, charset: "utf8mb4", collation: "utf8mb4_unicode_520_ci" do |t|
      t.bigint :actions_ruleset_id, unsigned: true, null: false
      t.bigint :actor_id, unsigned: true
      t.string :actor_type, limit: 100
      t.column :bypass_mode, "tinyint(3)", unsigned: true, null: false, default: 0
      t.string :type, limit: 100, null: false
      t.timestamps

      t.index [:actions_ruleset_id, :actor_id, :actor_type], unique: true, name: "index_actions_ruleset_bypass_actor_unique"
      t.index [:actions_ruleset_id, :type, :actor_id, :actor_type], name: "index_actions_ruleset_type_actor"
    end
  end
end
