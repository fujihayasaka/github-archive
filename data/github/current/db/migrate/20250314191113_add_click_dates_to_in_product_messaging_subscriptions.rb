# typed: true

class AddClickDatesToInProductMessagingSubscriptions < ActiveRecord::Migration[8.1]
  self.use_connection_class(ApplicationRecord::Domain::Users)

  def change
    change_table :in_product_messaging_subscriptions, bulk: true do |t|
      t.json     :metadata
    end
  end
end
