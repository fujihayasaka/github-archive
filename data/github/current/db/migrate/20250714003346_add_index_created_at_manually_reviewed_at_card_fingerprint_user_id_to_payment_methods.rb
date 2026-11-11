# typed: true
# frozen_string_literal: true

class AddIndexCreatedAtManuallyReviewedAtCardFingerprintUserIdToPaymentMethods < ActiveRecord::Migration[8.1]
  self.use_connection_class(ApplicationRecord::Domain::Users)
  def change
    change_table :payment_methods, bulk: true do |t|
      t.index [:created_at, :manually_reviewed_at, :card_fingerprint, :user_id], name: "idx_created_at_manually_reviewed_at_card_fingerprint_user_id"

      # Fix for the validation error in CI:
      # Some validations have failed:
      # SQL validation failed for table 'payment_methods':
      # - it is redundant to include the primary key as a prefix or suffix of these keys: [idx_pm_card_fingerprint_user_id_manually_reviewed_created_at_id(card_fingerprint, user_id, manually_reviewed_at, created_at, id)]
      t.remove_index [:card_fingerprint, :user_id, :manually_reviewed_at, :created_at, :id], name: "idx_pm_card_fingerprint_user_id_manually_reviewed_created_at_id"
      t.index [:card_fingerprint, :user_id, :manually_reviewed_at, :created_at], name: "idx_pm_card_fingerprint_user_id_manually_reviewed_created_at_id"
    end
  end
end
