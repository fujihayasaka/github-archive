# typed: true
class UpdateBillingBudgetsTableIntToBigInt < ActiveRecord::Migration[7.1]
  self.use_connection_class(ApplicationRecord::Domain::Billing)
  def change
    change_table :billing_budgets, bulk: true do |t|
      t.change :id, :bigint, null: false, auto_increment: true
      t.change :owner_id, :bigint, null: false
      t.change :spending_limit_in_subunits, :bigint, null: false, default: 0
    end
  end
end
