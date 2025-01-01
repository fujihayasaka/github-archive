# typed: true
# frozen_string_literal: true

module GitHub
  module Config
    module Azure
      def azure_translator_subscription_key
        @azure_translator_subscription_key ||= ENV.fetch("AZURE_TRANSLATOR_SUBSCRIPTION_KEY", nil)
      end
      attr_writer :azure_translator_subscription_key

      def azure_translator_subscription_region
        @azure_translator_subscription_region ||= ENV.fetch("AZURE_TRANSLATOR_SUBSCRIPTION_REGION", "eastus")
      end
      attr_writer :azure_translator_subscription_region

      def release_asset_azure_storage_account
        ENV["RELEASE_ASSET_AZURE_STORAGE_ACCOUNT"]
      end

      def release_asset_azure_storage_access_key
        ENV["RELEASE_ASSET_AZURE_ACCESS_KEY"]
      end
    end
  end

  extend Config::Azure
end
