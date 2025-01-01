class DropStageStates < ActiveRecord::Migration[5.0]
  def up
    drop_table :ingest_stage_states
  end

  def down
    raise ActiveRecord::IrreversibleMigration
  end
end
