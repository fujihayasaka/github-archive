# typed: true

class AddParentIdAndErrorMessageOnRepositoryOrchestrations < ActiveRecord::Migration[7.1]
  self.use_connection_class(ApplicationRecord::Domain::Repositories)

  def change
    change_table(:repository_orchestrations, bulk: true) do |t|
      t.bigint :parent_id, unsigned: true, null: true
      t.string :error_message, null: true
      t.index [:parent_id, :state], unique: false, name: "index_parent_id_state"
      t.change_null :repository_id, true
    end
  end
end
