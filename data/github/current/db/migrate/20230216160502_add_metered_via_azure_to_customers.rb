# typed: true
class AddMeteredViaAzureToCustomers < ActiveRecord::Migration[7.1]
  def change
    add_column :customers, :metered_via_azure, :boolean, null: false, default: false, after: :metered_plan
  end
end
