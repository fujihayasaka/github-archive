# typed: true

class AddIndexOnBillingPlatformEnabledProducts < ActiveRecord::Migration[8.1]
  self.use_connection_class(ApplicationRecord::Domain::Users)

  def change
    change_table :billing_platform_enabled_products, bulk: true do |t|
      t.remove_index :cohort_name
      t.index [:cohort_name, :migration_date, :failed_at]
    end
  end
end
