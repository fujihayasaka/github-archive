# rubocop:disable GitHub/DoNotAddUniqueIndexToExistingColumn
# typed: true
# frozen_string_literal: true

# rubocop:disable Naming/InclusiveLanguage the db table is named BlacklistedPaymentMethods.
# It will be changed to BlocklistedPaymentMethods.
class AddPolymorphicIndexesToBlocklistedPaymentMethods < ActiveRecord::Migration[8.1]
  self.use_connection_class(ApplicationRecord::Domain::Users)

  def change
    change_table :blacklisted_payment_methods, bulk: true do |t|
      t.index [:unique_number_identifier, :owner_id, :owner_type],
              unique: true,
              name: "index_blacklisted_payment_methods_on_identifier_and_owner"

      t.index [:paypal_email, :owner_id, :owner_type],
              unique: true,
              name: "index_blacklisted_payment_methods_on_paypal_email_and_owner"
    end
  end
end
# rubocop:enable Naming/InclusiveLanguage, GitHub/DoNotAddUniqueIndexToExistingColumn
