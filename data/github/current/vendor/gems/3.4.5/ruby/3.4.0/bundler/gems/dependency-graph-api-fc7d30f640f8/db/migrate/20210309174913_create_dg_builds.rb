class CreateDgBuilds < ActiveRecord::Migration[6.0]
  def change
    create_table :dg_builds, id: false, options: "ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci" do |t|
      t.bigint :id, primary_key: true, null: false, auto_increment: true, limit: 20, unsigned: true
      t.string :external_build_id
      t.integer :build_type_id, null: false
      t.datetime :scanned_at
      t.datetime :created_at
      t.datetime :updated_at
    end

    add_index :dg_builds, [:build_type_id, :external_build_id], name: "index_dg_builds_on_build_type_id_and_build_id"
  end
end
