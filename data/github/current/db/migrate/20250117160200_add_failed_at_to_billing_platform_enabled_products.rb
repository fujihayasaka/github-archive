# typed: true

class AddFailedAtToBillingPlatformEnabledProducts < ActiveRecord::Migration[8.1]
  self.use_connection_class(ApplicationRecord::Domain::Users)

  def change
    add_column :billing_platform_enabled_products, :failed_at, :datetime, null: true, precision: 6
  end
end
