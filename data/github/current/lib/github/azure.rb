# typed: true
# frozen_string_literal: true

module GitHub
  module Azure
    autoload :HttpClient, "github/azure/http_client"
    autoload :AadTokenClient, "github/azure/aad_token_client"
    autoload :AadCodeGrantTokenClient, "github/azure/aad_code_grant_token_client"
    autoload :ConstantTokenClient, "github/azure/constant_token_client"
    autoload :AzureEnvironmentSelector, "github/azure/azure_environment_selector"
    autoload :TranslatorClient, "github/azure/translator_client"
    autoload :AzureEnvironments, "github/azure/azure_environment"
    autoload :ActiveDirectoryServiceSettings, "github/azure/active_directory_service_settings"
    autoload :ApplicationTokenProvider, "github/azure/application_token_provider"
  end
end
