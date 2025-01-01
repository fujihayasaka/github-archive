# typed: true

class AddRulesetBypassActorsType < ActiveRecord::Migration[8.1]
  self.use_connection_class(ApplicationRecord::Domain::Repositories)
  def up
    change_table(:repository_ruleset_bypass_actors, bulk: true) do |t|
      t.column :type, :string, limit: 100, null: true, default: nil
      t.change :actor_id, :bigint, unsigned: true, null: true
      t.change :actor_type, :string, limit: 100, null: true
      t.index [:repository_ruleset_id, :type, :actor_id, :actor_type], name: :index_repository_ruleset_type_actor
    end
  end

  def down
    change_table(:repository_ruleset_bypass_actors, bulk: true) do |t|
      t.remove_column :type
      t.change :actor_id, :bigint, unsigned: true, null: false
      t.change :actor_type, :string, limit: 100, null: false
      t.remove_index [:repository_ruleset_id, :type, :actor_id, :actor_type], name: :index_repository_ruleset_type_actor
    end
  end
end
