# typed: true
class AddBilledViaBillingPlatformToCustomer < ActiveRecord::Migration[7.1]
  def change
    change_table :customers, bulk: true do |t|
      t.column :billed_via_billing_platform, :boolean, null: false, default: false, after: :metered_via_azure
      t.index [:billed_via_billing_platform]
    end
  end
end
