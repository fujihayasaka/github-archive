# typed: true
# frozen_string_literal: true

# rubocop:disable Naming/InclusiveLanguage the db table is named BlacklistedPaymentMethods.
# It will be changed to BlocklistedPaymentMethods.
class ChangeUserIdToNullableOnBlocklistedPaymentMethods < ActiveRecord::Migration[8.1]
  self.use_connection_class(ApplicationRecord::Domain::Users)

  def change
    change_table :blacklisted_payment_methods, bulk: true do |t|
      t.change :user_id, :bigint, unsigned: true, null: true
    end
  end
end
# rubocop:enable Naming/InclusiveLanguage
