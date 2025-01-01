# typed: true
# frozen_string_literal: true

module GitHub
  module AzureServiceBus
    autoload :ConnectionConfiguration, "github/azure_service_bus/connection_configuration"
    autoload :Consumer, "github/azure_service_bus/consumer"
    autoload :Executor, "github/azure_service_bus/executor"
    autoload :HttpClient, "github/azure_service_bus/http_client"
    autoload :Message, "github/azure_service_bus/message"
    autoload :QueueClient, "github/azure_service_bus/queue_client"
    autoload :SharedAccessSigner, "github/azure_service_bus/shared_access_signer"
    autoload :SubscriptionClient, "github/azure_service_bus/subscription_client"
  end
end
