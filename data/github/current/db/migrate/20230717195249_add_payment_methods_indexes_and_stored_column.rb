# typed: true
class AddPaymentMethodsIndexesAndStoredColumn < ActiveRecord::Migration[7.1]
  self.use_connection_class(ApplicationRecord::Domain::Users)

  def change
    change_table :payment_methods, bulk: true do |t|
      t.virtual :card_fingerprint, type: :string, as: "COALESCE(NULLIF(paypal_email, ''), NULLIF(unique_number_identifier, ''))", limit: 255, stored: true

      t.index [:card_fingerprint, :user_id, :manually_reviewed_at, :created_at, :id], name: "idx_pm_card_fingerprint_user_id_manually_reviewed_created_at_id"
    end
  end
end
