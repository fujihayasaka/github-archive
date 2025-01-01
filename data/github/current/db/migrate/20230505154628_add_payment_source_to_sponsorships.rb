# typed: true

class AddPaymentSourceToSponsorships < ActiveRecord::Migration[7.1]
  self.use_connection_class(ApplicationRecord::Domain::Sponsors)

  def change
    change_table :sponsorships, bulk: true do |t|
      t.integer :payment_source, default: 0, null: false, after: :paid

      t.index [:payment_source, :sponsorable_id]
    end
  end
end
