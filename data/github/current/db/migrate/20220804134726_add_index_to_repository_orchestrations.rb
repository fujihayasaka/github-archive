# typed: true
class AddIndexToRepositoryOrchestrations < ActiveRecord::Migration[7.1]
  self.use_connection_class(ApplicationRecord::Domain::Repositories)

  def change
    add_index :repository_orchestrations, [:updated_at, :state], unique: false, name: "index_updated_at_state"
  end
end
