# frozen_string_literal: true

module HandleWebhook
  class IssueComment
    class HandleReopenRequest
      def initialize(pull_request:, requester:)
        @pull_request = pull_request
        @requester = requester
      end

      def run
        return create_insufficient_permissions_comment unless user_has_write_permissions?

        return unless pull_request_closed?

        begin
          ReopenPullRequest.new(pull_request: pull_request).run
        rescue Octokit::UnprocessableEntity => e
          raise unless e.message.include?("already an open pull request")

          create_another_pr_already_open_comment
        end
      end

      private

      attr_reader :pull_request, :requester

      def create_insufficient_permissions_comment
        msg = "Sorry, only users with push access can use that command."
        CreateComment.new(pull_request: pull_request, comment_body: msg).run
      end

      def create_another_pr_already_open_comment
        msg =
          "An open PR from this branch already exists, so this PR can't "\
          "be re-opened."
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

      def pull_request_closed?
        !github_details.merged && github_details.state == "closed"
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
