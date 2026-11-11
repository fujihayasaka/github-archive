# typed: true
# frozen_string_literal: true

module GitHub
  module AzureServiceBus
    autoload :AadHttpClient, "github/azure_service_bus/aad_http_client"
    autoload :Consumer, "github/azure_service_bus/consumer"
    autoload :Executor, "github/azure_service_bus/executor"
    autoload :HttpClient, "github/azure_service_bus/http_client"
    autoload :IHttpClient, "github/azure_service_bus/i_http_client"
    autoload :Message, "github/azure_service_bus/message"
    autoload :QueueClient, "github/azure_service_bus/queue_client"
    autoload :SubscriptionClient, "github/azure_service_bus/subscription_client"
  end
end
