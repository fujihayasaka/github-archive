# typed: true

class DropMeteredUsageEntitlements < ActiveRecord::Migration[7.1]
  self.use_connection_class(ApplicationRecord::Billing)

  def change
    drop_table :metered_usage_entitlements
  end
end
