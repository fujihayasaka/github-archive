# frozen_string_literal: true

module HandleWebhook
  class IssueComment
    class HandleUnignoreRequest
      def initialize(pull_request:, requester:, comment_body:, comment_id:)
        @pull_request = pull_request
        @requester = requester
        @comment_body = comment_body.downcase
        @comment_id = comment_id
      end

      def run
        return create_invalid_command_comment unless valid_command?
        return create_permissions_comment unless user_has_write_permissions?

        @dep_name, @version_requirement = extract_dep_name_and_version_requirement
        return create_no_ignore_conditions_found_comment unless find_or_remove_ignore_condition

        handle_pull_request
      end

      private

      attr_reader :requester, :pull_request, :comment_body, :comment_id, :dep_name, :version_requirement

      def valid_command?
        comment_body.match?(UNIGNORE_VALIDATION_REGEX)
      end

      def extract_dep_name_and_version_requirement
        matches = comment_body.match(UNIGNORE_VALIDATION_REGEX)
        [matches[:dep_name], matches[:version_req]]
      end

      def create_invalid_command_comment
        msg = "Sorry, the command you entered is not valid. Valid commands:\n"\
              "`@dependabot unignore <dependency name> <ignore condition>`\n" \
              "`@dependabot unignore <dependency name> dependency`"

        CreateComment.new(pull_request: pull_request, comment_body: msg).run
      end

      def handle_pull_request
        recreate_and_create_unignore_comment
      end

      def recreate_and_create_unignore_comment
        HandleRecreateRequestJob.perform_later(pull_request: pull_request)
        create_unignore_comment
      end

      def create_unignore_comment
        msg = "OK, I will stop ignoring the #{dep_name} dependency"
        msg += " and its ignore condition [#{version_requirement}]" unless version_requirement.nil?
        msg += "."

        CreateComment.new(pull_request: pull_request, comment_body: msg).run
      end

      def create_no_ignore_conditions_found_comment
        msg = "No dependency name (#{dep_name}) or ignore conditions found to unignore."
        CreateComment.new(pull_request: pull_request, comment_body: msg).run
        false
      end

      def find_or_remove_ignore_condition
        FindOrRemoveIgnoreCondition.new(
          pull_request: pull_request,
          dep_name: dep_name,
          version_requirement_to_remove: version_requirement,
        ).run
      end

      def create_permissions_comment
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
    end
  end
end
