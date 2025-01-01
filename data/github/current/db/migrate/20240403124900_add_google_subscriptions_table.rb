class AddGoogleSubscriptionsTable < ActiveRecord::Migration[7.2]
  use_connection_class(ApplicationRecord::Domain::Billing)

  def change
    # Stores which Google subscriptions are active / used to purchase a product from GitHub.
    # This is a 0-to-1 relationship with the `subscription_items` table where no corresponding
    # record here represents the subscription item not being purchased via Google's Play Store while a record
    # here indicates the user has purchased the subscription item via Google's Play Store and will be billed
    # via Google.
    create_table :google_subscriptions,
      id: :bigint,
      unsigned: true,
      charset: "utf8mb4",
      collation: "utf8mb4_unicode_520_ci",
      comment: "Contains Google in-app purchase data for subscription_items records." do |t|

        t.bigint :subscription_item_id,
          unsigned: true,
          null: false,
          comment: "Reference to the subscription_items table."

        t.string :purchase_token,
          limit: 255,
          null: false,
          comment: "The purchase token for the purchase as provided by Google. We can use this value to query Google and request the most up-to-date info."

        t.timestamps

        # Supports cross-referencing by subscription_item:
        #   SELECT * FROM google_subscriptions WHERE subscription_item_id = 123
        # There should only be 0 or 1 corresponding google_subscriptions records per subscription_items record.
        t.index :subscription_item_id,
          unique: true,
          name: "idx_google_subscriptions_on_subscription_item_id"

        # Supports cross-referencing by the Google provided purchase_token:
        #   SELECT * FROM google_subscriptions WHERE purchase_token = 456
        # There should only be 0 or 1 corresponding google_subscriptions records per purchase_token record.
        t.index :purchase_token,
          unique: true,
          name: "idx_google_subscriptions_on_purchase_token"
      end
  end
end
