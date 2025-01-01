# typed: true

class AddMemexTemplates < ActiveRecord::Migration[7.1]
  self.use_connection_class(ApplicationRecord::Domain::Memexes)

  def change
    create_table :memex_templates, id: :bigint, unsigned: true, charset: "utf8mb4", collation: "utf8mb4_unicode_520_ci" do |t|
      t.column :owner_id, "bigint(20)", unsigned: true, null: false
      t.column :owner_type, "varchar(30)", null: false
      t.column :memex_project_id, "bigint(20)", unsigned: true, index: { unique: true }
      t.boolean :active, default: true, null: false

      t.timestamps

      t.index [:memex_project_id, :active], name: "index_memex_templates_on_memex_project_id_and_active"
      t.index [:owner_id, :owner_type, :active], name: "index_memex_templates_on_owner_id_and_owner_type_and_active"
    end
  end
end
