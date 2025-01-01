# typed: false
# frozen_string_literal: true

module Platform
  module Objects
    class GistFile < Platform::Objects::Base
      include GitHub::UTF8

      description "A file in a gist."

      # Determine whether the viewer can access this object via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_api_can_access?(permission, gist_file)
        gist = gist_file.gist
        gist.async_user.then do |owner|
          org = owner.is_a?(::Organization) ? owner : nil
          permission.access_allowed?(:get_gist_contents, resource: gist, current_org: org,
                                     current_repo: nil, allow_integrations: true,
                                     allow_user_via_granular_actor: true)
        end
      end

      # Determine whether the viewer can see this object (called internally).
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_viewer_can_see?(permission, gist_file)
        permission.spam_check(gist_file.gist)
      end

      scopeless_tokens_as_minimum

      field :name, String, description: "The gist file name.", null: true

      def name
        filename = @object.tree_entry.name
        return filename if filename.nil? || filename.empty?
        utf8(@object.tree_entry.name)
      end

      field :encoded_name, String,
        description: "The file name encoded to remove characters that are invalid in URL paths.",
        null: true

      def encoded_name
        if name.present?
          Addressable::URI.encode_component(name, Addressable::URI::CharacterClasses::PATH)
        end
      end

      field :is_image, Boolean, null: false, description: "Indicates if this file is an image."

      def is_image
        @object.tree_entry.image?
      end

      field :extension, String, null: true, description: "The file extension from the file name."

      def extension
        @object.tree_entry.extension
      end

      field :is_truncated, Boolean, null: false,
        description: "Whether the file's contents were truncated."

      def is_truncated
        @object.tree_entry.truncated?
      end

      field :can_render, Boolean, null: false,
        description: "Indicates whether this file can be rendered. Will return false if the file is binary or too large.",
        visibility: :internal

      def can_render
        blob = @object.tree_entry
        blob.can_render? && blob.viewable?
      end

      field :language, Language, "The programming language this file is written in.", null: true

      def language
        lang = @object.tree_entry.language
        LanguageName.find_by_name(lang.name) if lang
      end

      field :size, Integer, description: "The gist file size in bytes.", null: true

      def size
        @object.tree_entry.size
      end

      field :encoding, String, description: "The gist file encoding.", null: true

      def encoding
        @object.tree_entry.encoding
      end

      field :text, String,
        description: "UTF8 text data or null if the file is binary", null: true do
        argument :truncate, Integer, "Optionally truncate the returned file to this length.",
          required: false
      end

      def text(truncate: nil)
        blob = @object.tree_entry
        if blob.binary?
          nil
        elsif truncate
          blob.data.first(truncate)
        else
          blob.data
        end
      end

      field :lines, [String],
        description: "Get the text data of this file as separate lines with syntax highlighting. If any syntax highlighting is applied, HTML strings will be returned.",
        null: false, required_capabilities: [:mobile_only_schema_mask] do
        argument :limit, Integer, "Optionally limit how many lines are returned.",
          default_value: 100, required: false
      end

      def lines(limit: nil)
        blob = @object.tree_entry
        if blob.binary?
          []
        else
          lines = blob.colorized_lines
          lines = lines.take(limit) if limit
          lines
        end
      end
    end
  end
end
