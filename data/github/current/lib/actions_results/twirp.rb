# typed: true
# frozen_string_literal: true

module ActionsResults
  module Twirp
    extend T::Sig

    autoload :BaseClient, "actions_results/twirp/base_client"
    autoload :NullClient, "actions_results/twirp/null_client"

    autoload :ArtifactClient, "actions_results/twirp/artifact_client"
    autoload :JobSummaryClient, "actions_results/twirp/job_summary_client"
    autoload :LogClient, "actions_results/twirp/log_client"
    autoload :StepsClient, "actions_results/twirp/steps_client"

    class BaseError < StandardError; attr_accessor :msg; end
    class Error < BaseError; end
    class ServiceUnavailableError < Error; end

    sig { returns(ArtifactClient) }
    def self.artifact_client
      @artifact_client ||= ArtifactClient.new
    end

    sig { returns(JobSummaryClient) }
    def self.job_summary_client
      @job_summary_client ||= JobSummaryClient.new
    end

    sig { returns(LogClient) }
    def self.log_client
      @log_client ||= LogClient.new
    end

    sig { returns(StepsClient) }
    def self.steps_client
      @steps_client ||= StepsClient.new
    end
  end
end
