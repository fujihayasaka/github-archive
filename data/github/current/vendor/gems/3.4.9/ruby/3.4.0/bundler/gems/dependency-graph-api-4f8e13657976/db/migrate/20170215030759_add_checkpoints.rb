class AddCheckpoints < ActiveRecord::Migration[5.0]
  def change
    create_table :checkpoints, options: "ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci" do |t|
      t.string :name
      t.integer :last_checkpointed_id
      t.timestamps
    end
  end
end
