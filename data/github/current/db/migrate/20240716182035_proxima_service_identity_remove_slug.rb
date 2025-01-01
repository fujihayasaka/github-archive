class ProximaServiceIdentityRemoveSlug < ActiveRecord::Migration[8.0]
  self.use_connection_class(ApplicationRecord::Domain::Integrations)

  def up

    # HERE BE DRAGONS! Since the migration is removing an index and a column it must be wrapped in change_table. This is,
    # enforced by the GitHub/UseChangeTable rubocop rule. However, if we use t.remove_index on a multi-column index,
    # only a single column is removed which is not what we want. By using remove_index we get the behavior we want
    # but now the Lint/UnusedBlockArgument rubocop rule will fail. Normally, we would just omit the block paramater, but
    # that causes GitHub/UseChangeTable to throw a false positive. Additionally, not explicitly using the block parameter
    # will cause GitHub/UseChangeTable to fail. Therefore we need to disable both rules.
    #
    # rubocop:disable Lint/UnusedBlockArgument
    # rubocop:disable GitHub/UseChangeTable
    change_table :proxima_service_identities, bulk: true do |t|
      remove_index :proxima_service_identities, [:tenant_slug, :service_name], unique: true, name: "index_proxima_service_identities_on_tenant_slug_and_service_name"
      remove_column :proxima_service_identities, :tenant_slug
    end
  end

  def down
    change_table :proxima_service_identities, bulk: true do |t|
      unless column_exists?(:proxima_service_identities, :tenant_slug)
        t.string :tenant_slug, limit: 60
      end

      unless index_exists?(:proxima_service_identities, [:tenant_slug, :service_name], unique: true, name: "index_proxima_service_identities_on_tenant_slug_and_service_name")
        t.index [:tenant_slug, :service_name], unique: true, name: "index_proxima_service_identities_on_tenant_slug_and_service_name"
      end
    end
  end
end
