# typed: strict
# frozen_string_literal: true

module Mobile
  module Google
    autoload :PlayStoreClient, "mobile/google/play_store_client"
    autoload :PlayStoreService, "mobile/google/play_store_service"
    autoload :SubscriptionPurchaseSummary, "mobile/google/subscription_purchase_summary"

    ANDROID_PUBLISHER_SCOPE = "https://www.googleapis.com/auth/androidpublisher"
    PRODUCTION_APP_ID = "com.github.android"
    STAFF_APP_ID = "com.github.android.staff"
    DEVELOPMENT_APP_ID = "com.github.android.dev"
    COPILOT_MONTHLY_SKU_ID = "com.github.android.copilot.monthly"
  end
end
