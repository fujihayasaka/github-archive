# typed: strict
# frozen_string_literal: true

class Licensing::AzureBlobClient
  extend T::Sig
  extend T::Helpers

  AZURE_STORAGE_TOKEN_AUDIENCE = "https://storage.azure.com/"

  class UploadError < StandardError; end
  class GetBlobError < StandardError; end

  sig { void }
  def initialize
    @client = T.let(nil, T.nilable(::Azure::Storage::Blob::BlobService))
  end

  sig { returns(::Azure::Storage::Blob::BlobService) }
  def client
    @client ||= begin
      azure_environment = GitHub::Azure::AzureEnvironmentSelector.get_azure_environment
      token_provider_settings = MsRestAzure::ActiveDirectoryServiceSettings.get_settings(azure_environment)
      token_provider_settings.token_audience = AZURE_STORAGE_TOKEN_AUDIENCE

      token_provider = MsRestAzure::ApplicationTokenProvider.new(
        GitHub.licensing_azure_spn_tenant_id,
        GitHub.licensing_azure_spn_client_id,
        GitHub.licensing_azure_spn_client_secret,
        token_provider_settings
      )
      token_provider.get_authentication_header
      access_token = token_provider.token
      token_credential = ::Azure::Storage::Common::Core::TokenCredential.new access_token
      token_signer = ::Azure::Storage::Common::Core::Auth::TokenSigner.new token_credential
      ::Azure::Storage::Blob::BlobService.create({
        storage_account_name: GitHub.licensing_azure_storage_account_name,
        signer: token_signer
      })
    end
  end

  sig { params(container_name: String, blob_name: String, data: String).returns(::Azure::Storage::Blob::Blob) }
  def upload(container_name, blob_name, data)
    begin
      response = client.create_block_blob(container_name, blob_name, data, options: {})
      GitHub.dogstats.increment("licensing.azure_blob_client.upload", tags: ["success:true"])
      response
    rescue ::Azure::Core::Error => error
      GitHub.dogstats.increment("licensing.azure_blob_client.upload", tags: ["success:false"])
      raise UploadError.new(error.message)
    end
  end

  sig { params(container_name: String, blob_name: String).returns([T.nilable(::Azure::Storage::Blob::Blob), T.nilable(String)]) }
  def get_blob(container_name, blob_name)
    begin
      response = client.get_blob(container_name, blob_name)
      GitHub.dogstats.increment("licensing.azure_blob_client.get_blob", tags: ["success:true"])
      response
    rescue ::Azure::Core::Error => error
      if error.is_a?(::Azure::Core::Http::HTTPError) && error.status_code == 404
        return nil, nil
      end
      GitHub.dogstats.increment("licensing.azure_blob_client.get_blob", tags: ["success:false"])
      raise GetBlobError.new(error.message)
    end
  end
end
