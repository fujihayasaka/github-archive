# typed: true

class DropSponsorshipSiftPaymentAbuseScores < ActiveRecord::Migration[8.2]
  self.use_connection_class(ApplicationRecord::Domain::Sponsors)

  def up
    drop_table :sponsorship_sift_payment_abuse_scores
  end

  def down
    create_table :sponsorship_sift_payment_abuse_scores, id: :bigint, unsigned: true, charset: "utf8mb4", collation: "utf8mb4_unicode_520_ci" do |t| # rubocop:disable GitHub/NoNewTablesOnSharedDbClusters
      t.bigint :sponsorship_id, null: false, unsigned: true
      t.bigint :sponsor_id, null: false, unsigned: true
      t.bigint :sponsorable_id, null: false, unsigned: true
      t.decimal :value, precision: 10, scale: 9, null: false
      t.json :reasons
      t.bigint :plan_subscription_id, null: false, unsigned: true
      t.bigint :billing_transaction_id, null: false, unsigned: true
      t.bigint :line_item_id, null: false, unsigned: true
      t.timestamps null: false

      t.index :line_item_id, unique: true, name: "index_sponsorship_sift_payment_abuse_scores_on_line_item_id"
      t.index [:sponsorship_id, :value], name: "index_sponsorship_sift_payment_abuse_scores_sponsorship_id_value"
      t.index [:billing_transaction_id, :value], name: "idx_sponsorship_sift_payment_abuse_scores_billing_xact_id_value"
      t.index [:sponsor_id, :value], name: "index_sponsorship_sift_payment_abuse_scores_on_sponsor_id_value"
      t.index [:sponsorable_id, :value], name: "index_sponsorship_sift_payment_abuse_scores_sponsorable_id_value"
      t.index :plan_subscription_id, name: "index_sponsorship_sift_payment_abuse_scores_plan_subscription_id"
    end
  end
end
