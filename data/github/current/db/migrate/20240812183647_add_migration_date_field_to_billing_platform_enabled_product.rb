class AddMigrationDateFieldToBillingPlatformEnabledProduct < ActiveRecord::Migration[8.0]
  self.use_connection_class(ApplicationRecord::Domain::Users)

  def change
    change_table :billing_platform_enabled_products, bulk: true do |t|
      t.datetime :migration_date, precision: 6, null: true, comment: "Date when Business migrated from meuse over to billing-platform"
    end
  end
end
