class CreateSubscriptionChangeRequests < ActiveRecord::Migration[8.0]
  self.use_connection_class(ApplicationRecord::Domain::Billing)

  def up
    create_table :sales_serve_subscription_change_requests, id: :bigint, unsigned: true, charset: "utf8mb4", collation: "utf8mb4_unicode_520_ci" do |t|
      # Add columns
      t.string :request_uuid, limit: 36, null: false
      t.bigint :customer_id, unsigned: true, null: false
      t.string :zuora_subscription_id, limit: 32, null: false
      t.timestamps

      # Add indexes
      t.index :request_uuid, unique: true, name: "index_sales_serve_sub_change_requests_on_request_uuid"
      t.index :customer_id, name: "index_sales_serve_sub_change_requests_on_customer_id"
    end
  end

  def down
    drop_table :sales_serve_subscription_change_requests, if_exists: true
  end
end
