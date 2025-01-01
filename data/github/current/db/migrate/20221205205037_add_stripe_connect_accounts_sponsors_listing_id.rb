# typed: true
# frozen_string_literal: true

class AddStripeConnectAccountsSponsorsListingId < ActiveRecord::Migration[7.1]
  self.use_connection_class(ApplicationRecord::Billing)

  def up
    change_table :stripe_connect_accounts, bulk: true do |t|
      t.bigint :sponsors_listing_id, null: false, default: 0, after: :payable_id, unsigned: true

      t.change :payable_type, "varchar(32)", default: "SponsorsListing"
      t.change :payable_id, :bigint, unsigned: true, default: 0

      t.index [:sponsors_listing_id, :payouts_enabled],
        name: "idx_stripe_connect_accounts_sponsors_listing_id_payouts_enabled"
      t.index [:sponsors_listing_id, :billing_country],
        name: "idx_stripe_connect_accounts_sponsors_listing_id_billing_country"
      t.index [:sponsors_listing_id, :verification_status, :country],
        name: "idx_stripe_connect_accounts_spon_listing_id_verif_status_country"
    end
  end

  def down
    change_table :stripe_connect_accounts, bulk: true do |t|
      t.remove :sponsors_listing_id

      t.change :payable_type, "varchar(32)", default: nil
      t.change :payable_id, :bigint, unsigned: true, default: nil

      t.remove_index name: "idx_stripe_connect_accounts_sponsors_listing_id_payouts_enabled"
      t.remove_index name: "idx_stripe_connect_accounts_sponsors_listing_id_billing_country"
      t.remove_index name: "idx_stripe_connect_accounts_spon_listing_id_verif_status_country"
    end
  end
end
