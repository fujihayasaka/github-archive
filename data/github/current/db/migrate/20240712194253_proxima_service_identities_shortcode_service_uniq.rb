# rubocop:disable GitHub/DoNotAddUniqueIndexToExistingColumn
class ProximaServiceIdentitiesShortcodeServiceUniq < ActiveRecord::Migration[7.2]
  self.use_connection_class(ApplicationRecord::Domain::Integrations)

  def change
    change_table :proxima_service_identities, bulk: true do |t|
      # non unique index should already exist from 20240523134227_add_shortcode_to_proxima_service_identities.rb
      if index_exists?(:proxima_service_identities, [:tenant_shortcode, :service_name])
        t.remove_index [:tenant_shortcode, :service_name]
      end

      # rubocop:disable GitHub/AvoidRedundantIndex
      t.index [:tenant_shortcode, :service_name], unique: true, name: "idx_tenant_shortcode_service_name_uniq"
    end
  end
end
