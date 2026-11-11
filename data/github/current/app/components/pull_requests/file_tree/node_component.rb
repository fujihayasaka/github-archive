# typed: true
# frozen_string_literal: true

module PullRequests
  module FileTree
    class NodeComponent < ApplicationComponent
      include DiffHelper
      include FileFilterHelper
      attr_reader :default_hydro_payload, :node, :file_types, :subitem, :codeowners, :viewed_files

      STATUS_ICONS = {
        "added" => {
          icon: "diff-added",
          title: "added",
          color: :success,
        },
        "removed" => {
          icon: "diff-removed",
          title: "removed",
          color: :danger,
        },
        "modified" => {
          icon: "diff-modified",
          title: "modified",
          color: :attention,
        },
        "renamed" => {
          icon: "diff-renamed",
          title: "modified",
          color: :muted,
        }
      }.freeze

      HYDRO_EVENT_ACTION = "file_selected"

      # Child component rendered by PullRequests::FileTree::RootNode,
      # representing an individual node in the file tree.
      #
      # node - An instance of GitHub::Diff::TreeNode
      # file_types - An array of Strings
      # subitem (optional) - Boolean for whether this node should be rendered as a subitem
      # viewed_files (optional) - An instance of PullRequestUserReviews
      # codeowners (optional) - An instance of Repository::Codeowners
      # default_hydro_payload (optional) - Hash of Hydro click tracking data.
      #                                 See HydroHelper#hydro_click_tracking_attributes
      def initialize(
        codeowners: nil,
        default_hydro_payload: {},
        file_types:,
        node:,
        subitem: false,
        viewed_files: nil
      )
        @node = node
        @file_types = file_types
        @subitem = subitem
        @viewed_files = viewed_files
        @codeowners = codeowners
        @default_hydro_payload = default_hydro_payload
      end

      # A browser-safe version of the node name. Forces binary node name to
      # UTF-8 encoding and scrubs any invalid characters (for cases where node
      # name contained incompatible character encodings).
      #
      # Returns UTF-8 encoded String
      memoize def display_name
        scrubbed_utf8(node.name)
      end

      # A browser-safe version of the node path. Forces binary node path to
      # UTF-8 encoding and scrubs any invalid characters (for cases where node
      # path contained incompatible character encodings).
      #
      # Returns UTF-8 encoded String
      memoize def display_path
        scrubbed_utf8(node.path)
      end

      def status_icon
        icon_arguments = STATUS_ICONS[node.status_label]
        Primer::Beta::Octicon.new(**icon_arguments, use_symbol: true)
      end

      def file_id
        diff_file_anchor(node.path)
      end

      def file_icon
        icon_type =
          if node.directory?
            :directory
          elsif node.submodule?
            :submodule
          elsif node.symlink?
            :symlink_directory
          else
            :file
          end
        GitHub::Files::IconComponent.new(type: icon_type, use_symbol: true)
      end

      # Should this file be hidden on initial page render?
      #
      # Returns Boolean
      def hidden?
        file_filtered?(
          path: node.path,
          deleted: node.deleted?,
          valid_file_types: file_types,
          viewed: marked_as_viewed?
        )
      end

      # Has the given path been marked as viewed?
      #
      # Returns Boolean
      memoize def marked_as_viewed?
        return false if node.directory?
        return false if viewed_files.blank?
        viewed_files.reviewed?(node.path)
      end

      # Should this node include information about its codeowners?
      #
      # Returns Boolean
      def include_codeowners?
        return false if node.directory?
        codeowners.present?
      end

      # A list of the codeowners for this node, including the current user if
      # they are a codeowner or member of any teams that are codeowners
      #
      # Returns Array
      memoize def codeowners_list
        return [] unless include_codeowners?

        @codeowners_list = codeowners_for_path(node.path)

        if path_owned_by_current_user?(path: node.path)
          @codeowners_list += [current_user]
        end

        @codeowners_list
      end

      def manifest_file?
        DependencyManifestFile.recognized_path?(path: node.path)
      end

      memoize def file_type
        get_file_type(node.path)
      end

      def hydro_tracking_attributes
        hydro_payload = default_hydro_payload.merge(action: HYDRO_EVENT_ACTION)
        hydro_payload[:data] ||= {}
        hydro_payload[:data][:path] = display_path
        hydro_payload[:data][:extension] = file_type

        hydro_click_tracking_attributes(FileTreeHelper::HYDRO_EVENT, hydro_payload)
      end

      private

      # A list of all of the codeowners for given path
      #
      # Returns an Array
      def codeowners_for_path(path)
        return [] unless codeowners.present?
        codeowners.owners_for_path(path)
      end

      # Is the current user a codeowner for the given path?
      #
      # Returns a boolean
      def path_owned_by_current_user?(path:)
        return false unless logged_in?
        return false unless include_codeowners?
        codeowners.owned_by?(owner: current_user, path: path)
      end
    end
  end
end
