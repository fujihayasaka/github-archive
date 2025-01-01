# typed: true
class AddMissingPaymentMethodIndexes < ActiveRecord::Migration[7.1]
  def change
    add_index :payment_methods, :paypal_email
  end
end
