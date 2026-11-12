class IncreaseLengthOfAttributionInDgAttributions < ActiveRecord::Migration[7.1]
  def down
    remove_index :dg_attributions, [:dg_package_versions_id, :attribution], unique: true, if_exists: true

    execute "ALTER TABLE dg_attributions ROW_FORMAT=DEFAULT;"

    change_column :dg_attributions, :attribution, :string, null: false, limit: 766, collation: "utf8mb4_0900_as_cs"

    add_index :dg_attributions, [:dg_package_versions_id, :attribution], unique: true
  end

  def up
    remove_index :dg_attributions, [:dg_package_versions_id, :attribution], unique: true, if_exists: true

    change_column :dg_attributions, :attribution, :string, null: false, limit: 16000, collation: "utf8mb4_0900_as_cs"

    execute "ALTER TABLE dg_attributions ROW_FORMAT=COMPRESSED;"

    add_index :dg_attributions, [:dg_package_versions_id, :attribution], unique: true, length: { attribution: 766 }
  end
end
