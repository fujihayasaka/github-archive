# typed: strict
# frozen_string_literal: true


class Billing::Azure::BlobClient
  extend T::Sig
  extend T::Helpers

  AZURE_STORAGE_TOKEN_AUDIENCE = "https://storage.azure.com/"
  USAGE_REPORT_AZURE_BLOB_CONTAINER = "billing-metered-exports-reports"


  sig { params(storage_config: Billing::Azure::Storage::Config).void }
  def initialize(storage_config)
    @client = T.let(nil, T.nilable(::Azure::Storage::Blob::BlobService))
    @storage_config = storage_config
  end

  sig { returns(::Azure::Storage::Blob::BlobService) }
  def client
    @client ||= begin
      azure_environment = GitHub::Azure::AzureEnvironmentSelector.get_azure_environment
      token_provider_settings = MsRestAzure::ActiveDirectoryServiceSettings.get_settings(azure_environment)
      token_provider_settings.token_audience = AZURE_STORAGE_TOKEN_AUDIENCE
      token_provider = MsRestAzure::ApplicationTokenProvider.new(
        @storage_config.tenant_id,
        @storage_config.client_id,
        @storage_config.client_secret,
        token_provider_settings
      )
      token_provider.get_authentication_header
      access_token = token_provider.token
      token_credential = ::Azure::Storage::Common::Core::TokenCredential.new access_token
      token_signer = ::Azure::Storage::Common::Core::Auth::TokenSigner.new token_credential
      ::Azure::Storage::Blob::BlobService.create({
        storage_account_name: @storage_config.storage_account_name,
        signer: token_signer
      })
    end
  end

  sig { params(container_name: String, blob_name: String, data: T.any(String, IO), options: T::Hash[Symbol, T.untyped]).returns(::Azure::Storage::Blob::Blob) }
  def upload(container_name, blob_name, data, options: {})
    begin
      response = client.create_block_blob(container_name, blob_name, data, options: options)
      GitHub.dogstats.increment("billing_azure_blob_client.upload", tags: ["success:true", "account:#{@storage_config.name}"])
      response
    rescue ::Azure::Core::Http::HTTPError => error
      GitHub.dogstats.increment(
        "billing_azure_blob_client.upload",
        tags: ["success:false", "status:#{error.status_code}}", "error:#{error.type}", "account:#{@storage_config.name}"]
      )
      raise error
    end
  end

  sig { params(container_name: String, blob_name: String).returns([T.nilable(::Azure::Storage::Blob::Blob), T.nilable(String)]) }
  def get_blob(container_name, blob_name)
    begin
      response = client.get_blob(container_name, blob_name)
      GitHub.dogstats.increment("billing_azure_blob_client.get_blob", tags: ["success:true", "account:#{@storage_config.name}"])
      response
    rescue ::Azure::Core::Http::HTTPError => error
      GitHub.dogstats.increment(
        "billing_azure_blob_client.get_blob",
        tags: ["success:false", "status:#{error.status_code}}", "error:#{error.type}", "account:#{@storage_config.name}"]
      )
      return nil, nil if error.status_code == 404
      raise error
    end
  end

  sig { params(container_name: String, blob_name: String, metadata: T::Hash[Symbol, T.untyped]).returns([T.nilable(::Azure::Storage::Blob::Blob), T.nilable(String)]) }
  def set_blob_metadata(container_name, blob_name, metadata)
    begin
      response = client.set_blob_metadata(container_name, blob_name, metadata)
      GitHub.dogstats.increment("billing_azure_blob_client.set_blob_metadata", tags: ["success:true", "account:#{@storage_config.name}"])
      response
    rescue ::Azure::Core::Http::HTTPError => error
      GitHub.dogstats.increment(
        "billing_azure_blob_client.set_blob_metadata",
        tags: ["success:false", "status:#{error.status_code}}", "error:#{error.type}", "account:#{@storage_config.name}"]
      )
      return nil, nil if error.status_code == 404
      raise error
    end
  end

  sig { params(container_name: String, blob_name: String).returns(T::Boolean) }
  def delete_blob(container_name, blob_name)
    begin
      response = client.delete_blob(container_name, blob_name)
      GitHub.dogstats.increment("billing_azure_blob_client.delete_blob", tags: ["success:true", "account:#{@storage_config.name}"])
      # The response from Azure is nil on success
      response.nil?
    rescue ::Azure::Core::Http::HTTPError => error
      GitHub.dogstats.increment(
        "billing_azure_blob_client.delete_blob",
        tags: ["success:false", "status:#{error.status_code}}", "error:#{error.type}", "account:#{@storage_config.name}"]
      )
      return false if error.status_code == 404
      raise error
    end
  end
end
