# typed: true
# frozen_string_literal: true

require "ms_rest_azure"
require "github/azure/ms_rest_monkey_patches"

module GitHub
  module Azure
    class AzureEnvironmentSelector
      # Get the MsRestAzure::AzureEnvironments::AzureEnvironment that
      # contains the configuration for the Azure environment in which this
      # instance is running.
      #
      # Returns MsRestAzure::AzureEnvironments::AzureEnvironment
      def self.get_azure_environment
        MsRestAzure::AzureEnvironments::AzureCloud
      end
    end
  end
end
