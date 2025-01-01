# typed: true
# frozen_string_literal: true

module Dependabot
  module Twirp
    autoload :BaseClient, "dependabot/twirp/base_client"
    autoload :NullClient, "dependabot/twirp/null_client"
    autoload :RepositoriesClient, "dependabot/twirp/repositories_client"
    autoload :RepositoryAccessServiceClient, "dependabot/twirp/repository_access_service_client"
    autoload :UpdateConfigsClient, "dependabot/twirp/update_configs_client"
    autoload :UpdateJobStatusDecorator, "dependabot/twirp/update_job_status_decorator"
    autoload :UpdateJobsClient, "dependabot/twirp/update_jobs_client"
    autoload :DebugClient, "dependabot/twirp/debug_client"
    autoload :SecretClient, "dependabot/twirp/secret_client"

    class BaseError < StandardError; attr_accessor :msg; end
    class Error < BaseError; end
    class ServiceUnavailableError < BaseError; end

    def self.repositories_client
      @repositories_client ||= RepositoriesClient.new
    end

    def self.repository_access_service_client
      @repository_access_service_client ||= RepositoryAccessServiceClient.new
    end

    def self.update_configs_client
      @update_configs_client ||= UpdateConfigsClient.new
    end

    def self.update_jobs_client
      @update_jobs_client ||= UpdateJobsClient.new
    end

    def self.debug_client
      @debugger_client ||= DebugClient.new
    end

    def self.secret_client
      @secret_client ||= SecretClient.new
    end
  end
end
