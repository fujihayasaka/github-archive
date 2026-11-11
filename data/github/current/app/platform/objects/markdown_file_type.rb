# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    class MarkdownFileType < Platform::Objects::Base
      include ActionView::Helpers::TagHelper

      graphql_name "MarkdownFileType"
      description "Represents a markdown file."


      # Determine whether the viewer can access this object via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_api_can_access?(permission, _object)
        # To access this non Active Record object the caller already need to get permissions for a repo and a commit
        true # rubocop:disable GitHub/GraphqlApiAuthorization
      end

      # Determine whether the viewer can see this object (called internally).
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_viewer_can_see?(permission, object)
        # To access this non Active Record object the caller already need to get permissions for a repo and a commit
        true # rubocop:disable GitHub/GraphqlApiAuthorization
      end

      required_capabilities [:mobile_only_schema_mask]

      minimum_accepted_scopes ["repo"]

      implements Interfaces::TextFile

      field :content_html, Scalars::HTML, description: "The syntax highlighted html for the markdown.", null: true

      def content_html
        Promise.all([@object.repository.async_default_branch, @object.repository.async_plan_customer]).then do |default_branch, _|
          root_commit_arguments = context.scoped_context[:root_commit_arguments]
          committish = if root_commit_arguments
            root_commit_arguments[:expression] || root_commit_arguments[:oid]
          else
            default_branch
          end

          if source = @object.symlink_source
            @object.info["path"] = source.path
          end

          formatter = Helpers::MarkdownFormatter.new(
            blob: @object.tree_entry,
            viewer: @context[:viewer],
            repository: @object.repository,
            committish: committish,
            absolute_path: true,
          )

          content = formatter.format_content
          return unless content

          ext = File.extname(@object.name).sub(".", "")
          content_tag :div, content.html_safe, # rubocop:disable Rails/OutputSafety
            :id => "readme",
            :class => ext,
            "data-path" => "#{h(@object.display_path)}"
        end
      end
    end
  end
end
