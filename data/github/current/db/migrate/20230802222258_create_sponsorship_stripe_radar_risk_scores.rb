# typed: true

class CreateSponsorshipStripeRadarRiskScores < ActiveRecord::Migration[7.1]
  self.use_connection_class(ApplicationRecord::Domain::Sponsors)

  def change
    create_table :sponsorship_stripe_radar_risk_scores, id: :bigint, unsigned: true, charset: "utf8mb4", collation: "utf8mb4_unicode_520_ci" do |t|
      t.column :value, :tinyint, unsigned: true, null: false
      t.json :outcome
      t.bigint :billing_transaction_id, null: false, unsigned: true
      t.timestamps null: false

      t.index [:billing_transaction_id, :value],
        name: "idx_sponsorship_stripe_radar_risk_scores_billing_xact_id_value"
    end
  end
end
