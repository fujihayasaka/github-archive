# typed: true
class AddRateLimitColumnToSiteScopedIntegrationInstallations < ActiveRecord::Migration[7.1]
  self.use_connection_class(ApplicationRecord::Domain::IntegrationsCollab)

  def up
    change_table :site_scoped_integration_installations, bulk: true do |t|
      t.column :rate_limit, :integer, default: nil, null: true

      # For lint rule GitHub/ExistingIdColumnsMustBeBigint.
      t.change :target_id, :bigint, unsigned: true, null: false
      t.change :integration_id, :bigint, unsigned: true, null: false
    end
  end

  def down
    change_table :site_scoped_integration_installations, bulk: true do |t|
      t.remove :rate_limit

      # Original column types
      t.change :target_id, :integer, null: false
      t.change :integration_id, :integer, null: false
    end
  end
end
