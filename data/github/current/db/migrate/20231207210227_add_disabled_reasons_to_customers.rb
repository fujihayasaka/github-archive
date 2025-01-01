class AddDisabledReasonsToCustomers < ActiveRecord::Migration[7.2]
  def change
    add_column :customers, :disabled_reasons, :text, null: true
  end
end
