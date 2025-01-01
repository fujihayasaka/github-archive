# typed: true
# frozen_string_literal: true

require "azure/storage/blob"
require "azure/storage/common"
require "azure/core/http/http_error"
require "github/turboscan_uploaders/i_uploader"

module GitHub
  module TurboscanUploaders
    class AzureManagedServiceIdentityTokenCredential < ::Azure::Storage::Common::Core::TokenCredential
      # This class acts as a bridge between an MsRestAzure token provider and an Azure Storage token credential.
      # I was a bit surprised there was nothing in the official libraries to do this, so if I've just missed it and you find one feel free to replace this.

      AZURE_MANAGED_SERVICE_IDENTITY_PORT = 50342
      MINIMUM_TOKEN_TTL = 1.minute

      def initialize(token_provider_settings, msi_id: nil)
        super(nil)
        @token_provider_settings = token_provider_settings
        @msi_id = msi_id
        token
      end

      def token
        @mutex.synchronize do
          if @token_expires.nil? || @token_expires < Time.now + MINIMUM_TOKEN_TTL
            token_provider = MsRestAzure::MSITokenProvider.new(AZURE_MANAGED_SERVICE_IDENTITY_PORT, @token_provider_settings, @msi_id)
            token_provider.get_authentication_header # We don't use the result of this, but it is required to populate the token field.
            @token = token_provider.token
            @token_expires = token_provider.token_expires_on
          end
          @token
        end
      end
    end

    # TurboscanUploaders::Azure is responsible for uploading files to Azure
    class Azure
      include GitHub::TurboscanUploaders::IUploader

      AZURE_STORAGE_TOKEN_AUDIENCE = "https://storage.azure.com/"

      def initialize(client = nil)
        @client = client
      end

      def client
        @client ||= begin
          options = {
            storage_account_name: GitHub.turboscan_azure_account_name,
          }
          if GitHub.turboscan_azure_storage_dns_suffix.present?
            options[:storage_dns_suffix] = GitHub.turboscan_azure_storage_dns_suffix
          end
          if GitHub.turboscan_azure_account_key.present?
            options[:storage_access_key] = GitHub.turboscan_azure_account_key
          else
            azure_environment = GitHub::Azure::AzureEnvironmentSelector.get_azure_environment
            token_provider_settings = MsRestAzure::ActiveDirectoryServiceSettings.get_settings(azure_environment)
            token_provider_settings.token_audience = AZURE_STORAGE_TOKEN_AUDIENCE
            token_credential = AzureManagedServiceIdentityTokenCredential.new(token_provider_settings)
            options[:signer] = ::Azure::Storage::Common::Core::Auth::TokenSigner.new token_credential
          end
          ::Azure::Storage::Blob::BlobService.create(options).tap do |client|
            client.with_filter(::Azure::Storage::Common::Core::Filter::LinearRetryPolicyFilter.new(retry_count = 3, retry_interval = 1))
          end
        end
      end

      sig { override.params(sarif: String, target: String).returns(String) }
      def upload(sarif, target)
        GitHub.dogstats.distribution("turboscan_client.azure_file_size", sarif.size)
        begin
          GitHub.dogstats.distribution_time("turboscan_client.azure_upload") do
            client.create_block_blob(
              GitHub.turboscan_azure_container,
              target,
              sarif
            )
          end
          target
        ensure
          if error = $!
            GitHub.dogstats.increment("turboscan_client.azure_upload_failure",
              tags: [
                "error:#{error.class.name}",
                error.respond_to?(:status_code) ? "status:#{error.status_code}" : nil,
              ].compact)
          end
        end
      end
    end
  end
end
