# typed: true
# frozen_string_literal: true

require "github/azure_token_credential"

module CodeScanningQueriesHelper
  AZURE_STORAGE_TOKEN_AUDIENCE = "https://storage.azure.com/"

  # Split 'array' into 'parts' arrays and return an array of those arrays, where
  # the sizes are as balanced as possible. If array.size < parts, only
  # array.size arrays are returned.
  def chunk(array, parts)
    parts = array.length if parts > array.length

    chunked = []
    parts.downto(1) do |i|
      chunked.push(array.slice!(0, (array.length.to_f / i).ceil))
    end

    chunked
  end

  # Returns an Azure client for the MRVA storage container.
  # This storage container is used for storing CodeQL databases, query packs,
  # instructions, and results for MRVA.
  def self.azure_client
    @azure_client_spn ||= ::Azure::Storage::Blob::BlobService.create(
      storage_account_name: GitHub.codeql_variant_analysis_azure_storage_account,
      signer: azure_token_signer
    )
  end

  def self.azure_token_signer
    azure_environment = GitHub::Azure::AzureEnvironmentSelector.get_environment
    token_provider_settings = GitHub::Azure::ActiveDirectoryServiceSettings.get_settings(azure_environment)
    token_provider_settings.token_audience = AZURE_STORAGE_TOKEN_AUDIENCE
    token_provider = GitHub::Azure::ApplicationTokenProvider.new(
      GitHub.turboscan_azure_storage_tenant_id,
      GitHub.turboscan_azure_storage_client_id,
      GitHub.turboscan_azure_storage_client_secret,
      token_provider_settings
    )
    token_credential = GitHub::AzureTokenCredential.new(token_provider)

    ::Azure::Storage::Common::Core::Auth::TokenSigner.new token_credential
  end
end
