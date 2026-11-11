# typed: true

class CreateBusinessInProductMessagingSubscriptions < ActiveRecord::Migration[8.2]
  self.use_connection_class(ApplicationRecord::Domain::InProductTargeting)
  def change
    create_table :business_in_product_messaging_subscriptions, id: :bigint, unsigned: true, charset: "utf8mb4", collation: "utf8mb4_unicode_520_ci" do |t|
      t.column :business_id, :bigint, unsigned: true, null: false
      t.boolean :promotion_subscribed, null: false, default: true
      t.boolean :tip_subscribed, null: false, default: true
      t.timestamps

      t.index [:business_id], unique: true
    end
  end
end
