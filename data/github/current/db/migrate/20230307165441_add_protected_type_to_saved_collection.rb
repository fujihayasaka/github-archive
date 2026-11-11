# typed: true

class AddProtectedTypeToSavedCollection < ActiveRecord::Migration[7.1]
  self.use_connection_class(ApplicationRecord::Domain::UsersCollab)

  def up
    change_table :saved_collections, bulk: true do |t|
      # enum defined in model
      t.column :protected_type, :integer, null: true,
        comment: "Denotes a collection's protected, system-reserved type."

      t.index [:dashboard_id, :protected_type], unique: true,
        name: "index_saved_collections_on_dashboard_id_and_protected_type"
    end
  end

  def down
    change_table :saved_collections, bulk: true do |t|
      t.remove :protected_type

      t.remove_index name: "index_saved_collections_on_dashboard_id_and_protected_type"
    end
  end
end
