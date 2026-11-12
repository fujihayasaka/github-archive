class CreateAttributions < ActiveRecord::Migration[7.1]
  def change
    drop_table :dg_attributions, if_exists: true

    create_table :dg_attributions do |t|
      t.string :attribution, limit: 766, null: false, collation: "utf8mb4_0900_as_cs"
      t.references :dg_package_versions, null: false

      t.timestamps
    end

    add_index :dg_attributions, [:dg_package_versions_id, :attribution], unique: true

    remove_index :dg_attributions, :dg_package_versions_id, if_exists: true
  end
end
