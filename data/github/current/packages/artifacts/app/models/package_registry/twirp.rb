# typed: true
# frozen_string_literal: true

module PackageRegistry
  module Twirp
    class BaseError < StandardError; attr_accessor :msg; end
    class Error < BaseError; end
    class ServiceUnavailableError < BaseError; end
    class AlreadyExistsError < BaseError; end
    class PermissionDeniedError < BaseError; end
    class FailedPreconditionError < BaseError; end
    class InvalidArgumentError < BaseError; end

    def self.metadata_client
      @metadata_client ||= MetadataClient.new
    end

    def self.fail_fast_metadata_client
      @fail_fast_metadata_client ||= MetadataClient.new(connection_open_timeout: 2, read_timeout: 3.5)
    end

    def self.migrator_client
      @migrator_client ||= MigratorClient.new
    end

    def self.action_packages_client
      @action_packages_client ||= ActionPackages::Client.new
    end
  end
end
