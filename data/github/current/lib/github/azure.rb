# typed: true
# frozen_string_literal: true

module GitHub
  module Azure
    autoload :HttpClient, "github/azure/http_client"
    autoload :AadTokenClient, "github/azure/aad_token_client"
    autoload :MsiTokenClient, "github/azure/msi_token_client"
    autoload :AadCodeGrantTokenClient, "github/azure/aad_code_grant_token_client"
    autoload :ConstantTokenClient, "github/azure/constant_token_client"
    autoload :KeyVaultClient, "github/azure/key_vault_client"
    autoload :TableClient, "github/azure/table_client"
    autoload :QueueClient, "github/azure/queue_client"
    autoload :AzureEnvironmentSelector, "github/azure/azure_environment_selector"
    autoload :TranslatorClient, "github/azure/translator_client"
  end
end
