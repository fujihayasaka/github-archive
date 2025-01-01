# typed: true
class DropCodespaceBillingMessages < ActiveRecord::Migration[7.1]
  self.use_connection_class(ApplicationRecord::Collab)

  def change
    drop_table :codespace_billing_messages
  end
end
