# typed: true

class AddUserIdToStripeWebhooks < ActiveRecord::Migration[7.2]
  self.use_connection_class(ApplicationRecord::Domain::UsersBallast)

  def change
    change_table :stripe_webhooks, bulk: true do |t|
      t.column :user_id, :bigint, unsigned: true, null: true, after: :account_id
      t.index :user_id
      t.change :id, :bigint, unsigned: true
    end
  end
end
