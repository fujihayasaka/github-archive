# typed: true
# frozen_string_literal: true

# rubocop:disable Naming/InclusiveLanguage the db table is named BlacklistedPaymentMethods.
# It will be changed to BlocklistedPaymentMethods.
class AddOwnerIdAndOwnerTypeToBlocklistedPaymentMethods < ActiveRecord::Migration[8.1]
  self.use_connection_class(ApplicationRecord::Domain::Users)

  def change
    change_table :blacklisted_payment_methods, bulk: true do |t|
      t.bigint :owner_id, unsigned: true, null: true
      t.string :owner_type, limit: 30, default: "User", null: false
      t.index [:owner_id, :owner_type]
    end
  end
end
# rubocop:enable Naming/InclusiveLanguage
