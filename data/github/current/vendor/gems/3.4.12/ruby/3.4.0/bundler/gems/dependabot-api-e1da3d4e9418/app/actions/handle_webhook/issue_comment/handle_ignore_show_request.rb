# frozen_string_literal: true

module HandleWebhook
  class IssueComment
    class HandleIgnoreShowRequest
      def initialize(pull_request:, requester:, comment_body:, comment_id:)
        @pull_request = pull_request
        @requester = requester
        @comment_body = comment_body.downcase
        @comment_id = comment_id
      end

      def run
        return create_permissions_comment unless user_has_write_permissions?
        return create_invalid_command_comment unless valid_command?

        @dep_name = extract_dep_name

        handle_show_ignore_condition_comment
      end

      private

      attr_reader :requester, :pull_request, :comment_body, :comment_id, :dep_name

      def valid_command?
        comment_body.match?(SHOW_IGNORE_CONDITIONS_REGEX)
      end

      def extract_dep_name
        comment_body.match(SHOW_IGNORE_CONDITIONS_REGEX)[:dep_name]
      end

      def create_invalid_command_comment
        msg = "Sorry, the command you entered is not valid for this pull request. "\
              "Valid command:\n"\
              "`@dependabot show <dependency name> ignore conditions`"

        CreateComment.new(pull_request: pull_request, comment_body: msg).run
      end

      def handle_show_ignore_condition_comment
        sorted_ignore_conditions = fetch_ignore_conditions

        msg = if sorted_ignore_conditions.blank?
                "No ignore conditions found for the dependency #{dep_name}"
              else
                format_ignore_conditions(sorted_ignore_conditions)
              end
        CreateComment.new(pull_request: pull_request, comment_body: msg).run
      end

      def fetch_ignore_conditions
        pull_request.update_config.ignore_conditions.where(dependency_name: dep_name).
          order(updated_at: :desc)
      end

      def format_ignore_conditions(sorted_ignore_conditions)
        # Map each condition to a row string
        table_rows = sorted_ignore_conditions.map do |ic|
          "| #{ic[:dependency_name]} | [#{ic[:version_requirement]}] |"
        end

        summary = "Ignore Conditions"
        build_table(summary, table_rows)
      end

      def build_table(summary, rows)
        table_header = "|Dependency| Ignore Condition|"
        table_divider = "|-|-|"
        table_body = rows.join("\r\n")
        body = [table_header, table_divider, table_body].join("\r\n")

        "<details>\r\n<summary>#{summary}</summary>\r\n<br />\r\n\r\n#{body}\r\n</details>"
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
