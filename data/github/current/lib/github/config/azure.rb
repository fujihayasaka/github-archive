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

      sig { returns(String) }
      def copilot_chat_attachment_azure_storage_account
        @copilot_chat_attachment_azure_storage_account ||= ENV.fetch("COPILOT_CHAT_ATTACHMENT_AZURE_STORAGE_ACCOUNT", "")
      end

      def copilot_chat_attachment_azure_storage_container
        @copilot_chat_attachment_azure_storage_container ||= begin
          env = GitHub.multi_tenant_enterprise? ? GitHub::Config::Proxima.current_stamp : "production"
          "github-#{env}-copilot-attachments"
        end
      end

      sig { returns(String) }
      def copilot_chat_attachment_azure_storage_base_url
        @copilot_chat_attachment_azure_storage_base_url ||= begin
          account = copilot_chat_attachment_azure_storage_account
          account.empty? ? "" : "https://#{account}.blob.core.windows.net/#{copilot_chat_attachment_azure_storage_container}/"
        end
      end

      sig { params(copilot_chat_attachment_azure_storage_account: String).void }
      attr_writer :copilot_chat_attachment_azure_storage_account

      sig { returns(String) }
      def copilot_chat_attachment_azure_storage_access_key
        @copilot_chat_attachment_azure_storage_access_key ||= ENV.fetch("COPILOT_CHAT_ATTACHMENT_AZURE_STORAGE_ACCESS_KEY", "")
      end

      sig { params(copilot_chat_attachment_azure_storage_access_key: String).void }
      attr_writer :copilot_chat_attachment_azure_storage_access_key

      sig { returns(String) }
      def copilot_chat_attachment_azure_storage_bucket
        @copilot_chat_attachment_azure_storage_bucket ||= "copilot-attachments"
      end

      sig { params(copilot_chat_attachment_azure_storage_bucket: String).void }
      attr_writer :copilot_chat_attachment_azure_storage_bucket

      sig { returns(String) }
      def models_attachment_azure_storage_account
        @models_attachment_azure_storage_account ||= ENV.fetch("MODELS_ATTACHMENT_AZURE_STORAGE_ACCOUNT", "")
      end

      sig { params(models_attachment_azure_storage_account: String).void }
      attr_writer :models_attachment_azure_storage_account

      sig { returns(T.nilable(String)) }
      def models_attachment_azure_storage_secret_key
        @models_attachment_azure_storage_secret_key ||= ENV["MODELS_ATTACHMENT_AZURE_ACCESS_KEY"]
      end

      sig { params(models_attachment_azure_storage_secret_key: String).void }
      attr_writer :models_attachment_azure_storage_secret_key

      sig { returns(String) }
      def models_attachment_azure_storage_bucket
        # Declared here https://github.com/github/memory-alpha/blob/4077b2bc1eb0c868c01b531d44dcf36e24559bcb/config/kustomize/components/production-config/config_maps/stores-config.yaml#L125
        @models_attachment_azure_storage_bucket ||= "models-attachments"
      end

      sig { params(models_attachment_azure_storage_bucket: String).void }
      attr_writer :models_attachment_azure_storage_bucket

    end
  end

  extend Config::Azure
end
