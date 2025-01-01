# rubocop:disable GitHub/DoNotAddUniqueIndexToExistingColumn

class AddIndexIntegrationsOnOwnerIdAndOwnerTypeAndSlug < ActiveRecord::Migration[7.2]
  def change
    change_table :integrations, bulk: true do |t|
      t.remove_index name: :index_integrations_on_slug, column: :slug, unique: true

      t.index [:owner_id, :owner_type, :slug], unique: true, name: "index_integrations_on_owner_id_and_owner_type_and_slug"
      t.index [:slug], unique: false, name: "index_integrations_on_slug"
    end
  end
end
