# typed: true

class AddIndexCardFingerprintCustomerIdToPaymentMethods < ActiveRecord::Migration[8.1]
  self.use_connection_class(ApplicationRecord::Domain::Users)

  def change
    change_table :payment_methods, bulk: true do |t|
      t.index [
        :created_at,
        :customer_id,
        :manually_reviewed_at,
        :card_fingerprint
      ], name: "idx_pm_created_at_customer_id_manually_reviewed_card_fingerprint"
    end
  end
end
