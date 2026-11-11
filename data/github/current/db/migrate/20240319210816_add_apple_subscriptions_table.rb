class AddAppleSubscriptionsTable < ActiveRecord::Migration[7.2]
  use_connection_class(ApplicationRecord::Domain::Billing)

  def change
    # Stores which Apple subscriptions are active / used to purchase a product from GitHub.
    # This is a 0-to-1 relationship with the `subscription_items` table where no corresponding
    # record here represents the subscription item not being purchased via Apple's App Store while a record
    # here indicates the user has purchased the subscription item via Apple's App Store and will be billed
    # via Apple.
    create_table :apple_subscriptions,
      id: :bigint,
      unsigned: true,
      charset: "utf8mb4",
      collation: "utf8mb4_unicode_520_ci",
      comment: "Contains Apple in-app purchase data for subscription_items records." do |t|

      t.bigint :subscription_item_id,
        unsigned: true,
        null: false,
        comment: "Reference to the subscription_items table."

      t.string :original_transaction_id,
        limit: 64,
        null: false,
        comment: "The original transaction ID for the purchase as provided by Apple. We can use this value to query Apple and request the most up-to-date info."

      t.timestamps

      # Supports cross-referencing by subscription_item:
      #   SELECT * FROM apple_subscriptions WHERE subscription_item_id = 123
      # There should only be 0 or 1 corresponding apple_subscriptions records per subscription_items record.
      t.index :subscription_item_id,
        unique: true,
        name: "idx_apple_subscriptions_on_subscription_item_id"

      # Supports cross-referencing by the Apple provided original_transaction_id:
      #   SELECT * FROM apple_subscriptions WHERE original_transaction_id = 456
      # We are not 100% sure this should be unique at this point but will most likely start by backing
      # the corresponding ActiveRecord model with a uniqueness constraint.
      t.index :original_transaction_id,
        name: "idx_apple_subscriptions_on_original_transaction_id"
    end
  end
end
