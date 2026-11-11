# typed: true

class AddStateToSponsorships < ActiveRecord::Migration[7.1]
  self.use_connection_class(ApplicationRecord::Domain::Sponsors)

  def change
    change_table :sponsorships, bulk: true do |t|
      t.integer :state, default: 0, null: false, after: :active

      t.index [:state, :expires_at]
      t.index [:state, :paid_at]
      t.index [:state, :invoiced_sponsorship_transfer_id, :paid, :expires_at],
        name: "index_sponsorships_on_state_invoiced_xfer_id_paid_expires_at"
      t.index [:state, :sponsor_id, :invoiced_sponsorship_transfer_id, :paid,
        :expires_at], name: "idx_sponsorships_on_state_sponsor_invoiced_xfer_id_paid_expires"
      t.index [:privacy_level, :sponsorable_id, :state, :sponsor_id],
        name: "index_sponsorships_on_privacy_level_sponsorable_state_sponsor"
      t.index [:sponsorable_id, :state, :subscribable_id],
        name: "index_sponsorships_on_sponsorable_id_state_subscribable_id"
    end
  end
end
