# typed: true
# frozen_string_literal: true

require "azure/storage/common"
require "azure/storage/common/client_options_error"
require "azure/storage/blob"
require "azure/core/http/http_error"

module GHECAdmin
  class StorageError < StandardError; end

  AZURE_STORAGE_TOKEN_AUDIENCE = "https://storage.azure.com/"

  class Storage
    attr_reader :filename, :bucket_type

    def self.make(filename, bucket_type, type = nil)
      AzureStorage.new(filename, bucket_type)
    end

    def initialize(filename, bucket_type)
      @filename = filename
      @bucket_type = bucket_type
    end

    def exists?
    end

    def cleanup
    end

    def get
    end

    def size
    end

    def store(contents)
    end
  end

  class AzureStorage < Storage
    def exists?
      return true if @headers
      azure_errors do
        @headers = azure_blob_client.get_blob_properties(container_name, filename)
      end
      true
    rescue GHECAdmin::StorageError
      false
    end

    def cleanup
      return unless exists?
      azure_errors do
        azure_blob_client.delete_blob(container_name, filename)
      end
      @body = nil
      @headers = nil
    end

    def get
      fetch unless @body
      yield @body
    end

    def size
      fetch unless @headers
      @headers.properties[:content_length]
    end

    def store(contents, content_type)
      azure_errors do
        azure_blob_client.create_block_blob(
          container_name,
          filename,
          contents,
          options: {
            content_type: content_type
          }
        )
        true
      end
    rescue GHECAdmin::StorageError => e
      Failbot.report(e)
      false
    end

    private

    def azure_errors
      yield
    rescue ::Azure::Core::Http::HTTPError => error
      raise StorageError.new(error.message)
    rescue ::Azure::Storage::Common::InvalidOptionsError => e
      raise StorageError.new("Azure configuration invalid: #{e.message}")
    end

    def fetch
      azure_errors do
        @headers, @body = azure_blob_client.get_blob(container_name, filename)
      end
    end

    def container_name
      bucket_name = if bucket_type == :dormant_users
        "dormant-users"
      elsif bucket_type == :org_members
        "org-members"
      elsif bucket_type == :compliance_reports
        "compliance-reports"
      else
        bucket_type.to_s
      end
      "ghec-admin-reports-#{bucket_name}-exports"
    end

    def azure_token_signer
      @azure_token_signer ||= begin
        azure_environment = GitHub::Azure::AzureEnvironmentSelector.get_azure_environment
        token_provider_settings = MsRestAzure::ActiveDirectoryServiceSettings.get_settings(azure_environment)
        token_provider_settings.token_audience = AZURE_STORAGE_TOKEN_AUDIENCE

        token_provider = MsRestAzure::ApplicationTokenProvider.new(
          GitHub.enterprise_accounts_storage_azure_spn_tenant_id,
          GitHub.enterprise_accounts_storage_azure_spn_client_id,
          GitHub.enterprise_accounts_storage_azure_spn_client_secret,
          token_provider_settings
        )
        token_provider.get_authentication_header
        access_token = token_provider.token
        token_credential = ::Azure::Storage::Common::Core::TokenCredential.new access_token
        ::Azure::Storage::Common::Core::Auth::TokenSigner.new token_credential
      end
    end

    def azure_blob_client
      ::Azure::Storage::Blob::BlobService.create(
        storage_account_name: GitHub.enterprise_accounts_storage_azure_account_name,
        signer: azure_token_signer
      )
    end
  end
end
