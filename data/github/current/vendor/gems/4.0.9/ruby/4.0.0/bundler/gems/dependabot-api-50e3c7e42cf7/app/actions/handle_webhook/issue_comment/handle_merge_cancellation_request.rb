# frozen_string_literal: true

module HandleWebhook
  class IssueComment
    class HandleMergeCancellationRequest
      def initialize(pull_request:, requester:, comment_id:, comment_type:)
        @pull_request = pull_request
        @requester = requester
        @comment_id = comment_id
        @comment_type = comment_type
      end

      def run
        return create_insufficient_permissions_comment unless user_has_write_permissions?

        return unless pull_request.merge_requested? ||
                      pull_request.account.merge_on_approval?

        pull_request.update!(
          merge_requested: false,
          automerge_block_requested: true
        )
        create_acknowledgement_reaction_if_possible
        update_description_for_new_automerge_status
      end

      private

      attr_reader :pull_request, :requester, :comment_id, :comment_type

      def create_acknowledgement_reaction_if_possible
        CreateReaction.new(
          reaction: "+1",
          comment_id: comment_id,
          comment_type: comment_type,
          pull_request: pull_request,
        ).run
      end

      def update_description_for_new_automerge_status
        updated_body = github_details.body.sub(
          /#{Regexp.quote(automerge_start)}.*#{Regexp.quote(automerge_end)}/m,
          updated_automerge_description,
        )

        UpdatePullRequestBody.new(
          pull_request: pull_request,
          updated_body: updated_body,
        ).run
      end

      def updated_automerge_description
        updated_automerge_description =
          PullRequestFooter.new(
            update_job: pull_request.update_job,
            updated_dependencies: pull_request.updated_dependencies,
            outdated_ignore_conditions_removed: [],
            grouped_update: pull_request.grouped_update,
          ).automerge_text

        if updated_automerge_description.include?("automatically") ||
           pull_request.account.merge_on_approval?
          updated_automerge_description =
            automerge_start +
            "Dependabot will **not** automatically merge this PR "\
            "because @#{requester} cancelled automerging on it.\n\n" +
            automerge_end
        end

        updated_automerge_description
      end

      def github_details
        @github_details ||=
          installation_github_client.pull_request(
            pull_request.repo.github_id,
            pull_request.github_number,
          )
      end

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

      def automerge_start
        PullRequestFooter::AUTOMERGE_START
      end

      def automerge_end
        PullRequestFooter::AUTOMERGE_END
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
