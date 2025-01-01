# typed: true
class AddPaymentSourceToSponsorsActivities < ActiveRecord::Migration[7.1]
  self.use_connection_class(ApplicationRecord::Domain::Sponsors)

  def change
    change_table :sponsors_activities, bulk: true do |t|
      t.integer :payment_source, default: 0, null: false
    end
  end
end
