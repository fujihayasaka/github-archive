class CreateSubscriptionChangeRequestItems < ActiveRecord::Migration[8.0]
  self.use_connection_class(ApplicationRecord::Domain::Billing)

  def up
    create_table :sales_serve_subscription_change_request_items, id: :bigint, unsigned: true, charset: "utf8mb4", collation: "utf8mb4_unicode_520_ci" do |t|
      # Add columns
      t.bigint :change_request_id, unsigned: true, null: false
      t.column :status, :tinyint, unsigned: true, null: false, default: 0
      t.string :product_rate_plan_charge_id, limit: 32, null: false
      t.column :change_type, :tinyint, unsigned: true, null: false
      t.integer :quantity, unsigned: true
      t.decimal :price, precision: 10, scale: 2
      t.datetime :start_date, null: false, precision: 6
      t.datetime :end_date, null: false, precision: 6

      # Add indexes
      t.index :change_request_id, name: "index_sales_serve_sub_change_request_items_on_change_request_id"
    end
  end

  def down
    drop_table :sales_serve_subscription_change_request_items, if_exists: true
  end
end
