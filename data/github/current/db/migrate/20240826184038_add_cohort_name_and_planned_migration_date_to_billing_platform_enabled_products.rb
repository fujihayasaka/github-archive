class AddCohortNameAndPlannedMigrationDateToBillingPlatformEnabledProducts < ActiveRecord::Migration[8.0]
  self.use_connection_class(ApplicationRecord::Domain::Users)

  def change
    change_table :billing_platform_enabled_products, bulk: true do |t|
      t.string :cohort_name, null: true, comment: "The cohort the customer is in for migration to billing-platform"
      t.datetime :planned_migration_date, precision: 6, null: true, comment: "Date customer is scheduled to be migrated from meuse to billing-platform"

      t.index :cohort_name
      t.index [:customer_id, :cohort_name]
      t.index [:planned_migration_date, :migration_date]
    end
  end
end
