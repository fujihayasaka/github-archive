# typed: true
# frozen_string_literal: true

# rubocop:disable Naming/InclusiveLanguage the db table is named BlacklistedPaymentMethods.
# It will be changed to BlocklistedPaymentMethods.
class RemoveUserIdFromBlocklistedPaymentMethods < ActiveRecord::Migration[8.1]
  self.use_connection_class(ApplicationRecord::Domain::Users)

  def up
    change_table :blacklisted_payment_methods, bulk: true do |t|
      t.remove_index name: "index_blacklisted_payment_methods_on_identifier_and_user_id"
      t.remove_index name: "index_blacklisted_payment_methods_on_paypal_email_and_user_id"
      t.remove_index name: "index_blacklisted_payment_methods_on_user_id"
      t.remove :user_id
    end
  end

  def down
    change_table :blacklisted_payment_methods, bulk: true do |t|
      t.bigint :user_id, unsigned: true, null: true
      t.index :user_id, name: "index_blacklisted_payment_methods_on_user_id"
      t.index [:unique_number_identifier, :user_id], unique: true, name: "index_blacklisted_payment_methods_on_identifier_and_user_id"
      t.index [:paypal_email, :user_id], unique: true, name: "index_blacklisted_payment_methods_on_paypal_email_and_user_id"
    end
  end
end
