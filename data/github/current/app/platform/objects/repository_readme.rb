# typed: true
# frozen_string_literal: true
# DEPRECATED: this object is no longer needed see https://github.com/github/mobile/issues/550

module Platform
  module Objects
    class RepositoryReadme < Platform::Objects::Base
      include ActionView::Helpers::TagHelper
      model_name "TreeEntry"
      description "A readme in a repository."

      # Determine whether the viewer can access this object via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_api_can_access?(permission, tree_entry)
        # Although it's _not_ a tree, it responds to `.repository`,
        # so this check should work the same and be a bit DRYer:
        repo = tree_entry.repository
        permission.async_owner_if_org(repo).then do |org|
          permission.access_allowed?(:get_tree, resource: repo, current_repo: repo, current_org: org, allow_integrations: true, allow_user_via_granular_actor: true)
        end
      end

      # Determine whether the viewer can see this object (called internally).
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_viewer_can_see?(permission, object)
        permission.belongs_to_repository(object)
      end

      mobile_only true

      minimum_accepted_scopes ["repo"]

      field :repository, Objects::Repository, "The Repository the readme belongs to", null: false

      field :path, String, "The full path of the file.", null: true

      field :file_type, Unions::FileType, description: "The TreeEntry file type object", null: true

      def file_type
        Models::FileType.new(@object)
      end

      field :content_raw, String, description: "The raw content of the readme.", method: :data, null: true

      field :content_html, Scalars::HTML, description: "The html content of the readme.", null: true do
        # DEPRECATED: this was field is no longer needed see https://github.com/github/github/pull/138950
        argument :relative_paths, Boolean, "Whether or not to append the root path to local paths",
          required: false,
          default_value: false
      end

      def content_html(relative_paths: false)
        if source = @object.symlink_source
          @object.info["path"] = source.path
        end

        formatter = Helpers::MarkdownFormatter.new(
          blob: @object,
          viewer: @context[:viewer],
          repository: @object.repository,
          committish: @object.ref_name,
          absolute_path: true,
        )

        content = formatter.format_content
        return unless content

        ext = File.extname(@object.display_name).sub(".", "")
        content_tag :div, content.html_safe, # rubocop:disable Rails/OutputSafety
          :id => "readme",
          :class => ext,
          "data-path" => "#{force_escape_with_transcoding_guess(@object.path)}"
      end
    end
  end
end
