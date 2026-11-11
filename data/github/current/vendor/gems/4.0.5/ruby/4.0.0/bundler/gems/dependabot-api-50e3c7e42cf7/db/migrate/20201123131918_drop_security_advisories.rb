# frozen_string_literal: true

class DropSecurityAdvisories < ActiveRecord::Migration[6.0]
  def up
    drop_table :security_advisories
  end

  def down
    create_table :security_advisories, charset: "utf8mb4", collation: "utf8mb4_general_ci" do |t|
      t.column :dependency_name, "varchar(190)", null: false
      t.column :package_manager, "varchar(20)", null: false
      t.column :patched_versions, :text
      t.column :unaffected_versions, :text
      t.column :affected_versions, :text
      t.column :gsa_id, "varchar(19)", null: false
      t.timestamps null: false
    end

    add_index :security_advisories, %i(dependency_name package_manager)
  end
end
