class RemoveOwnerAssociationFromMemexTemplates < ActiveRecord::Migration[7.1]
  use_connection_class ApplicationRecord::Domain::Memexes

  def change
    change_table :memex_templates, bulk: true do |t|
      t.remove :owner_id, type: "bigint(20)", unsigned: true, null: false, after: :id
      t.remove :owner_type, type: "varchar(30)", null: false, after: :owner_id
      t.remove_index name: :index_memex_templates_on_owner_id_and_owner_type_and_active, column: [:owner_id, :owner_type, :active]
    end
  end
end
