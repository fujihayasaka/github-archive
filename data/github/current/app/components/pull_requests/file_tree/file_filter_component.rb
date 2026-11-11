# typed: true
# frozen_string_literal: true

module PullRequests
  module FileTree
    extend T::Helpers

    requires_ancestor { ApplicationController }
    class FileFilterComponent < ApplicationComponent
      include FileFilterHelper
      attr_reader :diff, :pull_id, :pull_codeowners

      def initialize(diff:, pull_id:, pull_codeowners:)
        @diff = diff
        @pull_id = pull_id
        @pull_codeowners = pull_codeowners
      end

      memoize def files_by_type
        diff.deltas.group_by do |delta, _memo|
          get_file_type(delta.new_file.path)
        end.delete_if { |k, _| k.blank? }.sort.to_h
      end

      def valid_file_types
        diff.file_types
      end

      # Should the option to show only files owned by current user be shown?
      # Returns true only when user owns at least one but not all files in the
      # diff, since there's nothing to filter if they own all of the files.
      #
      # Returns Boolean
      def show_owned_files_option?
        owned_files_count != diff.deltas.count && includes_owned_files?
      end

      def includes_manifest_files?
        diff.deltas.any? { |d| DependencyManifestFile.recognized_path?(path: d.path) }
      end

      def includes_deleted_files?
        diff.deltas.any? { |d| d.deleted? }
      end

      def filter_hydro_attributes_click(**args)
        payload = default_hydro_payload.merge(data: args)
        attributes = hydro_click_tracking_attributes("pull_request.user_action", payload)
        attributes["hydro-click"]
      end

      def filter_hydro_attributes_hmac(**args)
        payload = default_hydro_payload.merge(data: args)
        attributes = hydro_click_tracking_attributes("pull_request.user_action", payload)
        attributes["hydro-click-hmac"]
      end

      def owned_files_count
        owned_files.count
      end

      def file_type_count
        pluralize files_by_type.count, "file type"
      end

      def non_deleted_files_count(deltas)
        deltas.count { |d| !d.deleted? }
      end

      private

      memoize def default_hydro_payload
        {
          user_id: current_user&.id,
          pull_request_id: pull_id,
          category: "file_filter",
          action: "toggle_file_filter_option"
        }
      end

      def includes_owned_files?
        owned_files.any?
      end

      memoize def owned_files
        pull_codeowners.paths_for_owner(current_user)
      end
    end
  end
end
