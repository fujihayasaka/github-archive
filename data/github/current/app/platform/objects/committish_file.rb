# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    class CommittishFile < Platform::Objects::Base
      description "Represents a git blob that is bound under a commit."

      # Determine whether the viewer can access this object via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_api_can_access?(permission, _object)
        # TODO write proper permissions before making this object public
        permission.hidden_from_public?(self)
      end

      # Determine whether the viewer can see this object (called internally).
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_viewer_can_see?(permission, object)
        permission.belongs_to_repository(object)
      end

      minimum_accepted_scopes ["repo"]

      visibility :internal

      implements Platform::Interfaces::Node # rubocop:disable GitHub/GraphqlOnlyNewNodeImplementationForNewObject
      implements Interfaces::CommittishObject
      implements Interfaces::RepositoryNode
      implements Interfaces::UniformResourceLocatable

      global_id_field :id, description: "The Node ID of the CommittishFile object" # rubocop:disable GitHub/GraphqlOnlyNewNodeImplementationForNewObject

      url_fields description: "The HTTP URL for this file" do |file|
        file.uri
      end

      field :repository, Repository, "The repository associated with this file.", null: false
      field :revision, CommitRevision, "The commit revision object associated with this file.", null: false

      field :file_path, String, null: false, description: <<~MD
        The file's path from the tree root.

        Examples
        * "README.md"
        * "lib/main.c"
        * "src/example/foo/Bar.java"
      MD

      field :render_file_type, Enums::RenderFileType, null: true, description: "Detected Render file type." do
        argument :display_type, Enums::RenderDisplayType, "How the rendered file is displayed", required: false
      end

      def render_file_type(display_type: nil)
        viewscreen = CodeRenderingService.for(@object.tree_entry, display_type, @context[:viewer])
        if viewscreen.supports_view?
          return viewscreen.render_type
        end
        @object.tree_entry.render_file_type_for_display(display_type, viewer: @context[:viewer])
      end

      field :render_url, Scalars::URI, null: true, description: "URL of external rendered content" do
        argument :display_type, Enums::RenderDisplayType, "How the rendered file is displayed", required: false
      end

      def render_url(display_type: nil)
        viewscreen = CodeRenderingService.for(@object.tree_entry, display_type, @context[:viewer])
        return unless viewscreen.supports_view?

        viewscreen.url_for_display(commit_oid: @object.commit_oid)
      end

      field :blob, Objects::Blob, "The blob object this file path resolves to.", method: :async_object, null: false

      def self.load_from_global_id(id)
        Models::CommittishFile.load_from_global_id(id)
      end
    end
  end
end
