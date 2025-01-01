# typed: true
class CreateRulesetBypassActors < ActiveRecord::Migration[7.1]
  self.use_connection_class(ApplicationRecord::Repositories)

  def change
    create_table :repository_ruleset_bypass_actors, id: :bigint, unsigned: true, charset: "utf8mb4", collation: "utf8mb4_unicode_520_ci" do |t|

      t.bigint :repository_ruleset_id, unsigned: true, null: false

      t.bigint :actor_id, unsigned: true, null: false
      t.string :actor_type, limit: 100, null: false

      t.timestamps

      t.index [:repository_ruleset_id, :actor_id, :actor_type], unique: true, name: "index_repository_ruleset_actor"
    end
  end
end
