# typed: true
# frozen_string_literal: true

module Dependabot
  module Twirp
    class UpdateJobsClient < Dependabot::Twirp::BaseClient
      sig { params(repository_id: Integer, update_config_id: Integer).returns(DependabotApi::V1::ListJobsResponse) }
      def list_update_jobs(repository_id:, update_config_id:)
        rpc(:ListJobs, repository_github_id: repository_id, update_config_id: update_config_id)
      end

      sig { params(repository_id: Integer, update_job_id: Integer).returns(DependabotApi::V1::GetJobStatusResponse) }
      def get_job_status(repository_id:, update_job_id:)
        rpc(:GetJobStatus, repository_github_id: repository_id, update_job_id: update_job_id)
      end

      sig { params(repository_id: Integer, github_request_id: Integer).returns(DependabotApi::V1::GetJobStatusByGithubRequestIdResponse) }
      def get_job_status_by_github_request_id(repository_id:, github_request_id:)
        rpc(:GetJobStatusByGithubRequestId, repository_github_id: repository_id, github_request_id: github_request_id)
      end

      sig { params(repository_id: Integer, update_job_ids: T::Array[Integer]).returns(DependabotApi::V1::GetJobErrorsResponse) }
      def get_job_errors(repository_id:, update_job_ids:)
        # Don't make a remote call if we've been given an empty set, the calling code should
        # test the job ids are present before it invokes the client.
        raise ArgumentError, "update_job_ids cannot be empty" if update_job_ids.empty?

        rpc(:GetJobErrors, repository_github_id: repository_id, update_job_ids: update_job_ids)
      end

      private

      def twirp_class
        DependabotApi::V1::UpdateJobsClient
      end
    end
  end
end
