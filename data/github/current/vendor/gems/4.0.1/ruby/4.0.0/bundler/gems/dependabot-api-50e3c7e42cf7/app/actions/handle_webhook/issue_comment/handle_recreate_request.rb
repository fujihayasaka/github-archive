# frozen_string_literal: true

module HandleWebhook
  class IssueComment
    class HandleRecreateRequest
      def initialize(pull_request:, requester:, comment_id:, comment_type:)
        @pull_request = pull_request
        @requester = requester
        @comment_id = comment_id
        @comment_type = comment_type
      end

      def run
        return create_insufficient_permissions_comment unless user_has_write_permissions?
        return create_missing_group_comment if dependency_group_config_missing?

        create_acknowledgement_reaction_if_possible

        HandleRecreateRequestJob.perform_later(pull_request: pull_request)
      end

      private

      attr_reader :pull_request, :requester, :comment_id, :comment_type

      def user_has_write_permissions?
        @user_permission ||=
          RepoPermissionChecker.new(
            repo: pull_request.repo,
            user_github_login: requester,
          ).permission_level

        %w(write admin).include?(@user_permission)
      end

      def dependency_group_config_missing?
        return false if pull_request.update_job.security_updates_only?
        return false unless pull_request.grouped_update?
        return false if pull_request.multi_ecosystem_config_id?
        return true unless pull_request.dependency_group

        pull_request.dependency_group.deleted?
      end

      def create_missing_group_comment
        msg = "Sorry, the '#{group_name}' group has been removed from your config " \
              "so we do not know how to rebase this PR."
        CreateComment.new(pull_request: pull_request, comment_body: msg).run
      end

      def create_insufficient_permissions_comment
        msg = "Sorry, only users with push access can use that command."
        CreateComment.new(pull_request: pull_request, comment_body: msg).run
      end

      def create_acknowledgement_reaction_if_possible
        CreateReaction.new(
          reaction: "+1",
          comment_id: comment_id,
          comment_type: comment_type,
          pull_request: pull_request,
        ).run
      end

      def group_name
        pull_request.dependency_group&.name || "unknown"
      end
    end
  end
end
