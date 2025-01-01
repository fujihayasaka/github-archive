class AddConsumers < ActiveRecord::Migration[5.0]
  def change
    create_table :consumers, options: "ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci" do |t|
      t.integer :repository_id, null: false
      t.string :name, null: false
    end

    add_column :dependency_specifications, :dependent_type, :string, null: false
  end
end
