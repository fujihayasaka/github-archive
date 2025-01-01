# typed: true
# frozen_string_literal: true

require "azure/storage/blob"
require "azure/storage/common"
require "azure/core/http/http_error"
require "github/azure_token_credential"

module GitHub
  # TurboqualityAzure is responsible for uploading files to Azure
  class TurboqualityAzure
    AZURE_STORAGE_TOKEN_AUDIENCE = "https://storage.azure.com/"

    def initialize(client = nil)
      @client = client
      @mutex = Mutex.new
    end

    def client
      @mutex.synchronize do
        @client ||= begin
          options = {
            storage_account_name: GitHub.turboquality_azure_account_name,
          }
          signer = azure_token_signer
          if signer.present?
            options[:signer] = signer
          elsif GitHub.turboquality_azure_blob_host.present? && GitHub.turboquality_azure_account_key.present?
            options[:storage_blob_host] = "#{GitHub.turboquality_azure_blob_host}/#{GitHub.turboquality_azure_account_name}"
            options[:storage_access_key] = GitHub.turboquality_azure_account_key
          else
            raise ArgumentError, "No Azure storage account key or service principal provided."
          end
          ::Azure::Storage::Blob::BlobService.create(options)
        end
      end
    end

    def azure_token_signer
      if GitHub.turboscan_azure_storage_tenant_id.empty? || GitHub.turboscan_azure_storage_client_id.empty? || GitHub.turboscan_azure_storage_client_secret.empty?
        return nil
      end
      azure_environment = GitHub::Azure::AzureEnvironmentSelector.get_environment
      token_provider_settings = GitHub::Azure::ActiveDirectoryServiceSettings.get_settings(azure_environment)
      token_provider_settings.token_audience = AZURE_STORAGE_TOKEN_AUDIENCE
      token_provider = GitHub::Azure::ApplicationTokenProvider.new(
        # This Azure SPN is shared by all code scanning products,
        # but is named "turboscan" for legacy reasons.
        GitHub.turboscan_azure_storage_tenant_id,
        GitHub.turboscan_azure_storage_client_id,
        GitHub.turboscan_azure_storage_client_secret,
        token_provider_settings
      )
      token_credential = GitHub::AzureTokenCredential.new(token_provider)

      ::Azure::Storage::Common::Core::Auth::TokenSigner.new token_credential
    end

    sig { params(sarif: String, target: String).returns(String) }
    def upload(sarif, target)
      GitHub.dogstats.distribution("turboquality_client.azure_file_size", sarif.size)
      begin
        GitHub.dogstats.distribution_time("turboquality_client.azure_upload") do
          client.create_block_blob(
            GitHub.turboquality_azure_container,
            target,
            sarif
          )
        end
        target
      ensure
        if error = $!
          GitHub.dogstats.increment("turboquality_client.azure_upload_failure",
            tags: [
              "error:#{error.class.name}",
              error.respond_to?(:status_code) ? "status:#{error.status_code}" : nil,
            ].compact)
        end
      end
    end
  end
end
