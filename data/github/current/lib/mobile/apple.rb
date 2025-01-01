# typed: strict
# frozen_string_literal: true

module Mobile
  module Apple
    autoload :AppStoreClient, "mobile/apple/app_store_client"
    autoload :AppStoreService, "mobile/apple/app_store_service"
    autoload :SubscriptionSummary, "mobile/apple/subscription_summary"

    # Product SKUs stored on the Apple's side in AppStoreConnect.
    COPILOT_PRODUCT_ID = "Copilot"
    COPILOT_PRO_PLUS_PRODUCT_ID = "CopilotProPlus"
    PRO_PRODUCT_ID = "Pro"
  end
end
