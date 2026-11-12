class AddCheckpointUniqueIndex < ActiveRecord::Migration[5.0]
  def change
    add_index :checkpoints, [:name], unique: true
  end
end
