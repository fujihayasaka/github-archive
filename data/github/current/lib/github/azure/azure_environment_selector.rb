# typed: true
# frozen_string_literal: true

module GitHub
  module Azure
    class AzureEnvironmentSelector
      # Get the GitHub::Azure::AzureEnvironments::AzureEnvironment that
      # contains the configuration for the Azure environment in which this
      # instance is running.
      #
      # Returns GitHub::Azure::AzureEnvironments::AzureEnvironment
      def self.get_environment
        GitHub::Azure::AzureEnvironments::AzureCloud
      end
    end
  end
end
