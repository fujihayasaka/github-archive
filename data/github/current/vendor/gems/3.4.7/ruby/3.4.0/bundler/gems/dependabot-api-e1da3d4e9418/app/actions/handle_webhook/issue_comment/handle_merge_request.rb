# frozen_string_literal: true

module HandleWebhook
  class IssueComment
    class HandleMergeRequest
      include GitHub::Twirp::DependabotPullRequests::Helpers

      def initialize(pull_request:, requester:, comment_id:, comment_type:,
                     squash_commits: false, triggered_by_review_approval: false)
        @pull_request = pull_request
        @requester = requester
        @comment_id = comment_id
        @comment_type = comment_type
        @squash_commits = squash_commits
        @triggered_by_review_approval = triggered_by_review_approval
      end

      def run
        unless user_has_write_permissions?
          create_insufficient_permissions_comment unless triggered_by_review_approval?
          return
        end

        update_pull_request_flags
        create_acknowledgement_reaction_if_possible

        if pull_request.repo.config_feature_enabled?(:new_merge_command)
          # Immediately try to enable auto-merge. The rest of the logic will decide whether
          # to rebase/recreate if needed.
          result = EnableAutoMerge.new(pull_request: pull_request, squash: squash_commits?).run
          if result.clean?
            # The pull request can be merged immediately, so do it
            return MergePullRequest.new(pull_request: pull_request).run
          end

          if result.error?
            # An error occurred, so we should comment on the PR
            create_error_comment(result.message)
            return
          end
          # The merge was successful, fall-through and check for conflicts to do
          # the rebase/recreate if needed.
        end

        attempt_to_merge_pr
      end

      private

      attr_reader :pull_request, :requester, :comment_id, :comment_type

      def triggered_by_review_approval?
        @triggered_by_review_approval
      end

      def attempt_to_merge_pr
        if pull_request.in_state?(:merged, :closed)
          create_no_op_comment
        elsif pull_request.in_state?(:updating)
          create_merge_when_up_to_date
        elsif ci_passing? || no_ci?
          return if MergePullRequest.new(pull_request: pull_request).run

          create_merge_when_up_to_date
        else
          create_merge_when_ci_passes
        end
      rescue MergePullRequest::MergeNotPossible => e
        create_merge_not_possible_comment(e)
      end

      def squash_commits?
        @squash_commits
      end

      def update_pull_request_flags
        pull_request.update!(merge_requested: true, squash_requested: squash_commits?)
      end

      def create_merge_when_up_to_date
        update_description_for_merge_when_up_to_date
        CheckPullRequestForConflictsJob.perform_later(
          pull_request: pull_request,
          event_source: "action.handle_merge_request",
          manual: true
        )
      end

      def create_merge_when_ci_passes
        update_description_for_merge_when_ci_passes
        MergePullRequestJob.perform_later(pull_request: pull_request)
      end

      def no_ci?
        # Check whether the repo has no CI, and do a double-check that this PR
        # doesn't have any CI
        return false if pull_request.repo.has_ci?

        ci_status.blank?
      end

      def ci_passing?
        ci_status == resolve_ci_status_symbol(CiStatus::CI_STATUS_SUCCESS)
      end

      def ci_status
        @ci_status ||= pull_requests_client.
                       get_ci_status(repo: pull_request.repo, shas: [pull_request.head_commit_sha]).
                       fetch(pull_request.head_commit_sha, nil)
      rescue GitHub::Twirp::DependabotPullRequests::TransientServiceError,
             GitHub::Twirp::DependabotPullRequests::TransientTwirpError
        retrying ||= false
        raise if retrying

        retrying = true
        retry
      end

      def pull_requests_client
        @pull_requests_client ||=
          GitHub::Twirp::DependabotPullRequests.new(
            client: Dependabot::Application.github_twirp_client,
            tenant: pull_request.repo.account.tenant
          )
      end

      def create_acknowledgement_reaction_if_possible
        CreateReaction.new(
          reaction: "+1",
          comment_id: comment_id,
          comment_type: comment_type,
          pull_request: pull_request,
        ).run
      end

      def create_insufficient_permissions_comment
        msg = "Sorry, only users with push access can use that command."
        return if last_comment&.body == msg

        CreateComment.new(pull_request: pull_request, comment_body: msg).run
      end

      def create_merge_not_possible_comment(error)
        return if triggered_by_review_approval? &&
                  error.message.match?(/(code owner|approving) review/)
        return if last_comment&.body&.start_with?("Dependabot tried to merge")

        msg = "Dependabot tried to merge this PR, but received the following "\
              "error from GitHub:\n\n"\
              "```\n" \
              "#{error.message}\n"\
              "```"

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

      def last_comment
        @last_comment ||=
          installation_github_client.issue_comments(
            pull_request.repo.github_id,
            pull_request.github_number,
            per_page: 100,
          ).max_by(&:created_at)
      end

      def update_description_for_merge_when_ci_passes
        updated_automerge_description =
          automerge_start +
          "Dependabot will merge this PR once CI passes on it, as requested "\
          "by @#{requester}.\n\n" +
          automerge_end

        updated_body = github_details.body.sub(
          /#{Regexp.quote(automerge_start)}.*#{Regexp.quote(automerge_end)}/m,
          updated_automerge_description,
        )

        UpdatePullRequestBody.new(
          pull_request: pull_request,
          updated_body: updated_body,
        ).run
      end

      def update_description_for_merge_when_up_to_date
        updated_automerge_description =
          automerge_start +
          "Dependabot will merge this PR once it's up-to-date and CI "\
          "passes on it, as requested by @#{requester}.\n\n" +
          automerge_end

        updated_body = github_details.body.sub(
          /#{Regexp.quote(automerge_start)}.*#{Regexp.quote(automerge_end)}/m,
          updated_automerge_description,
        )

        UpdatePullRequestBody.new(
          pull_request: pull_request,
          updated_body: updated_body,
        ).run
      end

      def github_details
        @github_details ||=
          installation_github_client.pull_request(
            pull_request.repo.github_id,
            pull_request.github_number,
          )
      end

      def create_no_op_comment
        msg = no_op_comment_msg(state: pull_request.current_state)
        return if last_comment&.body == msg

        CreateComment.new(pull_request: pull_request, comment_body: msg).run
      end

      def no_op_comment_msg(state:)
        case state
        when "closed"
          "This PR is closed - you'll need to reopen it before merging."
        when "merged" then "This PR has already been merged! 🎉"
        else raise "Unexpected pull request state: #{state}"
        end
      end

      def create_error_comment(error_message)
        msg = "There was an error enabling auto-merge:\n\n```\n#{error_message}\n```"
        CreateComment.new(pull_request: pull_request, comment_body: msg).run
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
