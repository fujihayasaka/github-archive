# typed: true

class UpdateIndexAndUpgradeColumnsOnExternalGroups < ActiveRecord::Migration[8.1]
  self.use_connection_class(ApplicationRecord::Domain::Users)

  def up
    change_table :external_groups, bulk: true do |t|
      t.change :id, :bigint, unsigned: true
      t.change :provider_id, :bigint, unsigned: true

      t.remove_index name: "index_external_groups_on_provider_id_and_provider_type"
      t.index [:provider_id, :provider_type, :deleted_at],
        name: "index_external_groups_provider_id_provider_type_deleted_at"
    end
  end

  def down
    change_table :external_groups, bulk: true do |t|
      t.change :id, :integer
      t.change :provider_id, :integer

      t.remove_index name: "index_external_groups_provider_id_provider_type_deleted_at"
      t.index [:provider_id, :provider_type],
        name: "index_external_groups_on_provider_id_and_provider_type"
    end
  end
end
