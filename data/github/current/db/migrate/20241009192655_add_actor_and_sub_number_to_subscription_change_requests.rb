# typed: true
class AddActorAndSubNumberToSubscriptionChangeRequests < ActiveRecord::Migration[8.0]
  self.use_connection_class(ApplicationRecord::Domain::Billing)

  def change
    change_table :sales_serve_subscription_change_requests, bulk: true do |t|
      t.bigint :actor_id, unsigned: true, null: true
      t.string :zuora_subscription_number, limit: 32, null: true
    end
  end
end
