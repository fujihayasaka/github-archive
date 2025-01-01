class ChangeCheckpointsToBigint < ActiveRecord::Migration[5.0]
  def up
    change_column :checkpoints, :last_checkpointed_id, :bigint
  end

  def down
    change_column :checkpoints, :last_checkpointed_id, :integer
  end
end
