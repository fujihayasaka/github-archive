class CreateDgBuildTypes < ActiveRecord::Migration[6.0]
  def change
    create_table :dg_build_types, id: false, options: "ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci" do |t|
      t.integer :id, primary_key: true, null: false, auto_increment: true, unsigned: true
      t.integer :repository_id, null: false
      t.string :external_type_id
      t.string :external_type_id_display
      t.datetime :created_at
      t.datetime :updated_at
    end

    add_index :dg_build_types, [:repository_id, :external_type_id], name: "index_dg_build_types_on_repo_id_and_external_type_id"
  end
end
