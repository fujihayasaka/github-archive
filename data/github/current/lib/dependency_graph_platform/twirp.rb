# typed: true
# frozen_string_literal: true

module DependencyGraphPlatform
  module Twirp
    autoload :BaseClient, "dependency_graph_platform/twirp/base_client"
    autoload :HealthClient, "dependency_graph_platform/twirp/health_client"
    autoload :SbomClient, "dependency_graph_platform/twirp/sbom_client"
    autoload :AlertingClient, "dependency_graph_platform/twirp/alerting_client"

    class NonRetryableError < StandardError; end
    class BaseError < StandardError; attr_accessor :msg; end
    class Error < BaseError; end
    class ServiceUnavailableError < BaseError; end
    class InvalidConfigurationError < BaseError; end

    def self.health_client
      @health_client ||= HealthClient.new
    end
  end
end
