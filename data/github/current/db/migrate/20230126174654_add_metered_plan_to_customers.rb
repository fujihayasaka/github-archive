# typed: true

class AddMeteredPlanToCustomers < ActiveRecord::Migration[7.1]
  def change
    add_column :customers, :metered_plan, :boolean, null: false, default: false, after: :name
  end
end
