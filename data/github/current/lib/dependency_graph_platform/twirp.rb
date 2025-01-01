# typed: true
# frozen_string_literal: true

module DependencyGraphPlatform
  module Twirp
    autoload :BaseClient, "dependency_graph_platform/twirp/base_client"
    autoload :HealthClient, "dependency_graph_platform/twirp/health_client"
    autoload :ReachabilityClient, "dependency_graph_platform/twirp/reachability_client"

    class BaseError < StandardError; attr_accessor :msg; end
    class Error < BaseError; end
    class ServiceUnavailableError < BaseError; end
    class InvalidConfigurationError < BaseError; end

    def self.health_client
      @health_client ||= HealthClient.new
    end

    def self.reachability_client
      @reachability_client ||= ReachabilityClient.new
    end
  end
end
