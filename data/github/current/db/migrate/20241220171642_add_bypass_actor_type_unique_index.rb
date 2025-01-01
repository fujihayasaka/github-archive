# typed: true

class AddBypassActorTypeUniqueIndex < ActiveRecord::Migration[8.1]
  self.use_connection_class(ApplicationRecord::Repositories)

  # make the 'type' column not nullable

  def up
    change_table(:repository_ruleset_bypass_actors, bulk: true) do |t|
      t.change :type, :string, limit: 100, null: false
    end
  end

  def down
    change_table(:repository_ruleset_bypass_actors, bulk: true) do |t|
      t.change :type, :string, limit: 100, null: true, default: nil
    end
  end
end
