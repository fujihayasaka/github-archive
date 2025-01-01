# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    class TreeEntry < Platform::Objects::Base
      include GitHub::UTF8

      description "Represents a Git tree entry."

      # Determine whether the viewer can access this object via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_api_can_access?(permission, tree_entry)
        # Although it's _not_ a tree, it responds to `.repository`,
        # so this check should work the same and be a bit DRYer:
        permission.typed_can_access?("Tree", tree_entry)
      end

      # Determine whether the viewer can see this object (called internally).
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_viewer_can_see?(permission, object)
        permission.belongs_to_repository(object)
      end

      scopeless_tokens_as_minimum

      field :repository, Objects::Repository, "The Repository the tree entry belongs to", null: false

      field :name, String, "Entry file name.", null: false
      def name
        utf8(@object.name&.dup)
      end

      field :name_raw, Platform::Scalars::Base64String, "Entry file name. (Base64-encoded)", null: false, method: :name

      field :path, String, "The full path of the file.", null: true
      def path
        utf8(@object.path&.dup)
      end

      field :path_raw, Platform::Scalars::Base64String, "The full path of the file. (Base64-encoded)", null: true, method: :path

      field :extension, String, "The extension of the file", null: true

      field :mode, Integer, "Entry file mode.", null: false

      def mode
        @object.info["mode"]
      end

      field :size, Integer, "Entry byte size", null: false

      def size
        @object.size
      end

      field :type, String, "Entry file type.", null: false

      field :line_count, Int, "Number of lines in the file.", null: true

      field :oid, Scalars::GitObjectID, "Entry file Git object ID.", null: false

      field :object, Interfaces::GitObject, resolver_method: :git_object, description: "Entry file object.", null: true

      def git_object
        Loaders::GitObject.load(@object.repository, @object.info["oid"], path_prefix: @object.path)
      end

      field :content_html, Scalars::HTML, mobile_only: true, description: "Syntax highlighted html for the tree entry", null: true

      def content_html
        @object.async_colorized_lines.then do |colorized_lines|
          colorized_lines.join("\n").html_safe # rubocop:disable Rails/OutputSafety
        end
      end

      field :file_lines, [Objects::FileLine, null: true], mobile_only: true, description: "The lines for this file.", null: true

      def file_lines
        @object.async_file_lines
      end

      field :file_type, Unions::FileType, description: "The TreeEntry file type object", mobile_only: true, null: true

      def file_type
        Models::FileType.new(@object)
      end

      field :language, Language, "The programming language this file is written in.", null: true

      def language
        lang = @object.language
        LanguageName.find_by(name: lang.name) if lang
      end

      field :submodule, Objects::Submodule, description: "If the TreeEntry is for a directory occupied by a submodule project, this returns the corresponding submodule", null: true

      def submodule
        async_root_commit_oid.then do |oid|
          if oid
            @object.repository.async_submodule(oid, @object.path.b)
          else
            Promise.resolve(nil)
          end
        end
      end

      field :is_generated, Boolean, null: false, description: "Whether or not this tree entry is generated"

      def is_generated
        async_root_commit_oid.then do |oid|
          @object.async_generated?(oid)
        end
      end

      field :workflow, Objects::Workflow, description: "Workflow that represents this workflow file", method: :async_workflow, null: true, visibility: :internal

      private

      # Fetch the root oid that yielded this tree from scoped_context if
      # it's available there. If not (or if it's invalid), return the
      # default_oid (i.e. the HEAD commit of the default branch)
      def async_root_commit_oid
        raise_error = lambda do
          raise Platform::Errors::Execution.new(
            "NO_ROOT_COMMIT",
            "Can't provide subproject commit information without root commit context; try loading this TreeEntry from a commit instead.",
          )
        end
        async_root_commit_argument_oid.then do |oid|
          if oid
            Platform::Loaders::GitObject.load(@object.repository, oid, expected_type: :commit).then do |commit|
              if commit
                oid
              else
                raise_error.call
              end
            end
          else
            raise_error.call
          end
        end
      end

      def async_root_commit_argument_oid
        root_commit_arguments = context.scoped_context[:root_commit_arguments]
        if !root_commit_arguments
          Promise.resolve(nil)
        elsif root_commit_arguments[:oid]
          Promise.resolve(root_commit_arguments[:oid])
        elsif root_commit_arguments[:expression]
          @object.repository.async_ref_to_sha(root_commit_arguments[:expression].split(":").first)
        end
      end
    end
  end
end
