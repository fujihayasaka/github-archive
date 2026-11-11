# typed: true

class CreateInProductMessagingSubscriptions < ActiveRecord::Migration[8.1]
  self.use_connection_class(ApplicationRecord::Domain::Users)
  def change
    create_table :in_product_messaging_subscriptions, id: :bigint, unsigned: true, charset: "utf8mb4", collation: "utf8mb4_unicode_520_ci" do |t|
      t.column :user_id, :bigint, unsigned: true, null: false
      t.boolean :subscribed, null: false, default: true
      t.timestamps

      t.index [:user_id], unique: true
    end
  end
end
