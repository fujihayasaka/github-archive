# frozen_string_literal: true

module HandleWebhook
  class IssueComment
    class HandleCloseRequest
      def initialize(pull_request:, requester:)
        @pull_request = pull_request
        @requester = requester
      end

      def run
        return create_insufficient_permissions_comment unless user_has_write_permissions?

        return unless pull_request_open?

        ClosePullRequest.new(pull_request: pull_request).run
        CreateVersionSkipComment.new(pull_request: pull_request).run
      end

      private

      attr_reader :pull_request, :requester

      def create_insufficient_permissions_comment
        msg = "Sorry, only users with push access can use that command."
        CreateComment.new(pull_request: pull_request, comment_body: msg).run
      end

      def user_has_write_permissions?
        @user_permission ||=
          RepoPermissionChecker.new(
            repo: pull_request.repo,
            user_github_login: requester,
          ).permission_level

        %w(write admin).include?(@user_permission)
      end

      def pull_request_open?
        !github_details.merged && github_details.state != "closed"
      end

      def github_details
        @github_details ||=
          installation_github_client.pull_request(
            pull_request.repo.github_id,
            pull_request.github_number,
          )
      end

      def installation_github_client
        @installation_github_client ||=
          GitHubHelpers::ClientWithRetries.new(
            account: pull_request.repo.account,
          )
      end
    end
  end
end
