class AddDeliveryAtIndexToNewsletterSubscriptions < ActiveRecord::Migration[7.1]
  self.use_connection_class(ApplicationRecord::Domain::Users)

  def change
    reversible do |dir|
      change_table :newsletter_subscriptions, bulk: true do |t|
        dir.up do
          t.change :id, :bigint, unsigned: true
          t.change :user_id, :bigint, unsigned: true

          t.index [:name, :active, :next_delivery_at], name: "index_on_name_and_active_and_next_delivery_at"
          t.remove_index name: "index_newsletter_subscriptions_on_name"
        end
        dir.down do
          t.index :name
          t.remove_index name: "index_on_name_and_active_and_next_delivery_at"

          t.change :id, :int
          t.change :user_id, :int
        end
      end
    end
  end
end
