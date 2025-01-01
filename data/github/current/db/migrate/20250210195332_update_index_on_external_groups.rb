# typed: true

class UpdateIndexOnExternalGroups < ActiveRecord::Migration[8.1]
  self.use_connection_class(ApplicationRecord::Domain::Users)

  def up
    change_table :external_groups, bulk: true do |t|
      t.remove_index name: "index_external_groups_provider_id_provider_type_deleted_at"
      t.index [:provider_id, :provider_type, :deleted_at, :display_name],
        name: "index_external_groups_provider_id_type_deleted_at_display_name"
    end
  end

  def down
    change_table :external_groups, bulk: true do |t|
      t.remove_index name: "index_external_groups_provider_id_type_deleted_at_display_name"
      t.index [:provider_id, :provider_type, :deleted_at],
        name: "index_external_groups_provider_id_provider_type_deleted_at"
    end
  end
end
