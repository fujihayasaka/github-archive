# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    class IssuePlan < Platform::Objects::Base
      description "Represents the plan associated with an issue."

      visibility :under_development

      def self.async_api_can_access?(permission, object)
        issue = object[:issue]
        issue.async_repository.then do |repo|
          permission.typed_can_access?("Repository", repo)
        end
      end

      def self.async_viewer_can_see?(permission, object)
        issue = object[:issue]
        issue.async_repository.then do |repo|
          permission.typed_can_see?("Repository", repo)
        end
      end

      scopeless_tokens_as_minimum

      field :body,
        String,
        "The raw markdown content of the plan file.",
        null: true

      def body
        @object[:body]
      end

      field :body_html,
        Scalars::HTML,
        "The rendered HTML content of the plan file.",
        null: true

      def body_html
        content = @object[:body]
        return nil if content.nil?

        issue = @object[:issue]
        issue.async_body_context.then do |body_context|
          GitHub::Goomba::MarkdownPipeline.async_to_html(content, body_context)
        end
      end

      field :file_path,
        String,
        "The file path of the plan file (e.g. .github/plans/issue-<number>.md).",
        null: true

      def file_path
        @object[:file_path]
      end

      field :branch,
        String,
        "The branch name where the plan file is stored (linked branch or default branch).",
        null: true

      def branch
        @object[:branch]
      end

      field :error_message,
        String,
        "A user-facing error message indicating the plan could not be loaded.",
        null: true

      def error_message
        @object[:error_message]
      end
    end
  end
end
