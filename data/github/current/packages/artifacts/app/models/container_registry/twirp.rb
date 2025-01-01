# typed: true
# frozen_string_literal: true

module ContainerRegistry
  module Twirp
    class BaseError < StandardError; attr_accessor :msg; end
    class Error < BaseError; end
    class ServiceUnavailableError < Error; end
    class UnauthorizedError < Error; end

    def self.container_registry_client
      @container_registry_client ||= ContainerRegistryClient.new
    end
  end
end
