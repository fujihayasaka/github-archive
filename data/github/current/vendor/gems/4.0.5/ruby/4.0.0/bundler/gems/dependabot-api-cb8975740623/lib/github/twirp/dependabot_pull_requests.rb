# typed: true
# frozen_string_literal: true

require "twirp"

require_relative "dependabot_pull_requests/helpers"
require_relative "dependabot_pull_requests/twirp_error"
require_relative "dependabot_pull_requests/service_error"
require_relative "dependabot_pull_requests/dependency_file_protobuf_adapter"

module GitHub
  module Twirp
    class DependabotPullRequests
      extend T::Sig
      include Helpers

      sig do
        params(
          client: T.any(Twirp::Client, MonolithTwirp::Dependabot::PullRequests::V1::PullRequestAPIClient),
          tenant: T.any(Tenant, NullTenant)
        ).void
      end
      def initialize(client:, tenant:)
        @client = client
        @tenant = tenant
      end

      sig do
        params(
          repo: Repo,
          github_pr_numbers: T::Array[Integer],
          state: String,
          include_skipped_commits: T::Boolean
        ).returns(T::Array[MonolithTwirp::Dependabot::PullRequests::V1::PullRequest])
      end
      def get_pull_requests(repo:, github_pr_numbers:, state: "open", include_skipped_commits: false)
        response = log_timing do
          pull_requests_api.get_pull_requests(
            MonolithTwirp::Dependabot::PullRequests::V1::GetPullRequestsRequest.new(
              repository_id: repo.github_id,
              github_pr_numbers:,
              state:,
              include_skipped_commits:,
            ),
            headers,
          )
        end

        message = "Failed loading existing pull requests from GitHub"
        raise TwirpError.for_error(message, response.error) if response&.error
        raise ServiceError.for_error(message, response.data.error) if response.data&.error

        response.data.pull_requests.to_a
      end

      sig do
        params(
          repo: Repo,
          dependabot_branch_name: String,
          base_branch_name: T.nilable(String),
          base_commit_sha: String,
          require_up_to_date_base: T::Boolean
        ).returns(Symbol)
      end
      def check_pull_request_eligibility(repo:, dependabot_branch_name:, base_branch_name:,
                                         base_commit_sha:, require_up_to_date_base:)
        response = log_timing do
          pull_requests_api.check_pull_request_eligibility(
            MonolithTwirp::Dependabot::PullRequests::V1::CheckPullRequestEligibilityRequest.new(
              repository_id: repo.github_id,
              dependabot_branch_name:,
              base_commit_sha:,
              base_branch_name:,
              require_up_to_date_base:,
            ),
            headers
          )
        end

        message = "Failed to check whether PR can be created on GitHub"
        raise TwirpError.for_error(message, response.error) if response&.error
        raise ServiceError.for_error(message, response.data.error) if response.data&.error

        resolve_pr_eligibility_result_symbol(response.data.result)
      end

      sig do
        params(
          repo: Repo,
          dependabot_branch_name: String,
          base_commit_sha: String,
          commit_message: String,
          dependency_files: T::Array[Dependabot::DependencyFile]
        ).returns(MonolithTwirp::Dependabot::PullRequests::V1::PublishChangesResponse)
      end
      def publish_changes(repo:, dependabot_branch_name:, base_commit_sha:, commit_message:, dependency_files:)
        response = log_timing do
          pull_requests_api.publish_changes(
            MonolithTwirp::Dependabot::PullRequests::V1::PublishChangesRequest.new(
              repository_id: repo.github_id,
              dependabot_branch_name:,
              base_commit_sha:,
              commit_message:,
              dependency_files: dependency_files.map do |f|
                DependencyFileProtobufAdapter.new(f).to_proto
              end,
            ),
            headers
          )
        end

        message = "Failed publishing content to GitHub"
        raise TwirpError.for_error(message, response.error) if response&.error
        raise ServiceError.for_error(message, response.data.error) if response.data&.error

        response.data
      end

      sig do
        params(
          repo: Repo,
          base_branch_name: T.nilable(String),
          head_branch_name: String,
          pr_name: String,
          pr_description: String,
          labels: T::Array[MonolithTwirp::Dependabot::PullRequests::V1::Label],
          reviewers: T.nilable({ "reviewers" => T.nilable(T::Array[String]),
                                 "team_reviewers" => T.nilable(T::Array[String]), }),
          assignees: T::Array[String],
          milestone_number: T.nilable(Integer),
          dependabot_update_id: T.nilable(Integer)
        ).returns(MonolithTwirp::Dependabot::PullRequests::V1::PullRequest)
      end
      # rubocop:disable Metrics/MethodLength
      def create_pull_request(repo:, base_branch_name:, head_branch_name:, pr_name:, pr_description:,
                              labels:, reviewers:, assignees:, milestone_number:, dependabot_update_id:)
        response = log_timing do
          pull_requests_api.create_pull_request(
            MonolithTwirp::Dependabot::PullRequests::V1::CreatePullRequestRequest.new(
              repository_id: repo.github_id,
              base_branch_name:,
              head_branch_name:,
              pr_name:,
              pr_description: pr_description,
              labels:,
              reviewers: MonolithTwirp::Dependabot::PullRequests::V1::Reviewers.new(
                users: reviewers&.fetch("reviewers", []),
                teams: reviewers&.fetch("team_reviewers", [])
              ),
              assignees:,
              milestone_number:,
              dependabot_update_id:,
            ),
            headers
          )
        end

        message = "Failed to create PR on GitHub"
        raise TwirpError.for_error(message, response.error) if response&.error
        raise ServiceError.for_error(message, response.data.error, response.data.pull_request) if response.data&.error

        response.data&.pull_request
      end
      # rubocop:enable Metrics/MethodLength

      sig { params(repo: Repo, shas: T::Array[String]).returns(T::Hash[String, Symbol]) }
      def get_ci_status(repo:, shas:)
        return {} if shas.empty?

        response = log_timing do
          pull_requests_api.get_ci_status(
            MonolithTwirp::Dependabot::PullRequests::V1::GetCiStatusRequest.new(
              repository_id: repo.github_id,
              shas:,
            ),
            headers
          )
        end

        message = "Failed getting CI status from GitHub"
        raise TwirpError.for_error(message, response.error) if response&.error
        raise ServiceError.for_error(message, response.data.error) if response&.data&.error

        response.data.statuses.to_h.transform_values { |v| resolve_ci_status_symbol(v) }
      end

      private

      def log_timing
        start_time = Time.now.in_time_zone
        response = yield
        duration = Time.now.in_time_zone - start_time

        method_name = caller_locations(1, 1)&.first&.label || "unknown"
        MetricsClient.distribution(
          "twirp.github.dependabot_pull_requests.#{method_name}",
          duration,
          tags: { response_code: response&.error&.code || :ok }
        )

        response
      end

      sig { returns(T::Hash[String, String]) }
      def headers
        return {} unless Dependabot.proxima?
        raise GitHub::Twirp::Error, "Required Proxima tenant not set" if @tenant.slug.blank?

        {
          headers: { "X-GitHub-Tenant" => @tenant.slug },
        }
      end

      sig { returns(MonolithTwirp::Dependabot::PullRequests::V1::PullRequestAPIClient) }
      def pull_requests_api
        @pull_requests_api ||=
          if @client.is_a?(MonolithTwirp::Dependabot::PullRequests::V1::PullRequestAPIClient)
            @client
          else
            MonolithTwirp::Dependabot::PullRequests::V1::PullRequestAPIClient.new(@client.connection)
          end
      end
    end
  end
end
