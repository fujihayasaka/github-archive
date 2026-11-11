class CreateStageStates < ActiveRecord::Migration[5.0]
  def change
    create_table :ingest_stage_states, options: "ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci" do |t|
      t.string :stage
      t.text :metadata
      t.timestamps
    end
  end
end
