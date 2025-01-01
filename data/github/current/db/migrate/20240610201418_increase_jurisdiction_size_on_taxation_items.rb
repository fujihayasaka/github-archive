class IncreaseJurisdictionSizeOnTaxationItems < ActiveRecord::Migration[7.2]
  self.use_connection_class(ApplicationRecord::Billing)

  def change
    change_table :billing_transaction_tax_items, bulk: true do |t|
      t.change :jurisdiction, :string, null: false, limit: 100
      t.change :country, :string, null: true, limit: 3
    end
  end
end
