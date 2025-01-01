# typed: true
# frozen_string_literal: true

module Dependabot
  module Twirp
    class UpdateJobsClient < Dependabot::Twirp::BaseClient
      def list_update_jobs(repository_id:, update_config_id:)
        rpc(:ListJobs, repository_github_id: repository_id, update_config_id: update_config_id)
      end

      def get_job_logs(repository_id:, update_job_id:)
        rpc(:GetJobLogs, repository_github_id: repository_id, update_job_id: update_job_id)
      end

      def get_job_status_by_github_request_id(repository_id:, github_request_id:)
        rpc(:GetJobStatusByGithubRequestId, repository_github_id: repository_id, github_request_id: github_request_id)
      end

      def get_job_logs_by_github_request_id(repository_id:, github_request_id:)
        rpc(:GetJobLogsByGithubRequestId, repository_github_id: repository_id, github_request_id: github_request_id)
      end

      private

      def twirp_class
        DependabotApi::V1::UpdateJobsClient
      end
    end
  end
end
