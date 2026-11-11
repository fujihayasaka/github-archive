# typed: true

class CreateOrgInProductMessagingSubscriptions < ActiveRecord::Migration[8.2]
  self.use_connection_class(ApplicationRecord::Domain::InProductTargeting)
  def change
    create_table :org_in_product_messaging_subscriptions, id: :bigint, unsigned: true, charset: "utf8mb4", collation: "utf8mb4_unicode_520_ci" do |t|
      t.column :organization_id, :bigint, unsigned: true, null: false
      t.boolean :promotion_subscribed, null: false, default: true
      t.boolean :tip_subscribed, null: false, default: true
      t.timestamps

      t.index [:organization_id], unique: true
    end
  end
end
