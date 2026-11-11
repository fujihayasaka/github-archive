# typed: true
# frozen_string_literal: true

class UpdateTimestampPrecisionOnScopedIntegrationInstallationsOnLodge < ActiveRecord::Migration[7.2]
  # rubocop:todo GitHub/EnsureDomainIsolationInMigration (can be dropped once table move completed)
  self.use_connection_class(ApplicationRecord::Domain::IntegrationsLodge)

  def up
    return if GitHub.enterprise? || GitHub.multi_tenant_enterprise? || Rails.env.production? # rubocop:disable GitHub/DoNotBranchOnRailsEnv

    change_table :scoped_integration_installations, bulk: true do |t|
      t.change :created_at, :datetime, precision: 6, null: false
      t.change :updated_at, :datetime, precision: 6, null: false
    end
  end

  def down
    return if GitHub.enterprise? || GitHub.multi_tenant_enterprise? || Rails.env.production? # rubocop:disable GitHub/DoNotBranchOnRailsEnv

    change_table :scoped_integration_installations, bulk: true do |t|
      t.change :created_at, :datetime, precision: 0, null: false
      t.change :updated_at, :datetime, precision: 0, null: false
    end
  end
end
