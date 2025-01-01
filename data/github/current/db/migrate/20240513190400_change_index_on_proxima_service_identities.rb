# rubocop:disable GitHub/DoNotAddUniqueIndexToExistingColumn
class ChangeIndexOnProximaServiceIdentities < ActiveRecord::Migration[7.2]
  def change
    change_table :proxima_service_identities, bulk: true do |t|
      t.remove_index [:tenant_slug], unique: true, name: "index_proxima_service_identities_on_tenant_slug"

      t.index [:tenant_slug, :service_name], unique: true, name: "index_proxima_service_identities_on_tenant_slug_and_service_name"
    end
  end
end
