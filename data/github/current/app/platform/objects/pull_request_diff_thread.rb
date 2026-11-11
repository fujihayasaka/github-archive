# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    class PullRequestDiffThread < Platform::Objects::Base
      description "Provides a position in the diff for a comment thread on a Pull Request."

      # Determine whether the viewer can access this object via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_api_can_access?(permission, prd_thread)
        permission.load_pull_and_issue(prd_thread).then do |pull|
          permission.async_repo_and_org_owner(pull).then do |repo, org|
            pull.repository = repo # avoid association load down the line
            permission.access_allowed?(:list_pull_request_comments, repo: repo, current_org: org, resource: pull, allow_integrations: true, allow_user_via_granular_actor: true)
          end
        end
      end

      # Determine whether the viewer can see this object (called internally).
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_viewer_can_see?(permission, object)
        object.async_pull_request.then do |pull_request|
          permission.typed_can_see?("PullRequest", pull_request).then do |can_read_pull_request|
            can_read_pull_request && object.async_hide_from_user?(permission.viewer).then do |hide_from_viewer|
              !hide_from_viewer
            end
          end
        end
      end

      scopeless_tokens_as_minimum

      field :diff_lines, [Objects::DiffLine, null: true], description: "The diff lines associated with this thread.", null: true do
        argument :max_context_lines, Integer, default_value: 0, description: "Number of context lines to return.", required: false
      end

      def diff_lines(**arguments)
        @object.async_diff_lines(max_context_lines: arguments[:max_context_lines])
      end

      field :path, String, description: "Identifies the file path of this thread.", null: false

      field :path_digest, String, description: "The hashed file path of this thread", null: false

      field :start_line, Integer, description: "The start line in the file to which this thread refers.", method: :async_start_line_number, null: true

      field :start_line_type, String, required_capabilities: [:mobile_only_schema_mask], description: "The type of line the thread starts on (multi-line only)", null: true
      def start_line_type
        @object.async_start_line.then do |line|
          line_type(line) || end_line_type
        end
      end

      field :start_diff_side, Enums::DiffSide, description: "The side of the diff that the first line of the thread starts on", method: :start_side, null: true

      field :end_line, Integer, description: "The end line in the file to which this thread refers", method: :async_line, null: true

      field :end_line_type, String, required_capabilities: [:mobile_only_schema_mask], description: "The type of line the thread refers to.", null: true
      def end_line_type
        @object.async_end_line.then do |line|
          line_type(line)
        end
      end

      def line_type(line)
        return nil unless line
        case line.type
        when :addition then "+"
        when :deletion then "-"
        else
          ""
        end
      end

      field :end_diff_side, Enums::DiffSide, description: "The side of the diff on which this thread was placed.", method: :async_diff_side, null: false

      field :pull_request_commit, Objects::PullRequestCommit, visibility: :under_development, method: :async_pull_request_commit, description: "The commit to which this thread refers.", null: true

      field :original_start_line, Integer, visibility: :internal, description: "The original start line in the file to which this thread refers.", method: :async_original_start_line, null: true

      field :original_end_line, Integer, visibility: :internal, description: "The original end line in the file to which this thread refers.", method: :async_original_line, null: true
    end
  end
end
