# typed: true
# frozen_string_literal: true

module PullRequests
  module FileTreeHelper
    include DiffViewHelper
    include FeatureFlagHelper

    HYDRO_EVENT = "pull_request.user_action"
    HYDRO_EVENT_CATEGORY = "file_tree"
    MIN_FILE_COUNT_FOR_FILE_TREE = 1
    MIN_COMMIT_COUNT_FOR_FILE_TREE = 1

    # Determine the breakpoint at which the file tree should start being hidden.
    # File tree will be hidden at the resulting breakpoint and below.
    #
    # Returns Symbol
    def file_tree_hide_below_breakpoint
      if split_diff?
        :lg
      else
        :md
      end
    end

    # Check if the pull request file tree should be rendered as "open" and visible on initial page render.
    #
    # Returns Boolean
    def file_tree_visible?(file_count:)
      return @file_tree_visible if defined?(@file_tree_visible)
      return @file_tree_visible = false unless file_tree_available?(file_count: file_count)
      return @file_tree_visible = true if !T.unsafe(self).logged_in?
      @file_tree_visible = T.unsafe(self).current_user.settings.get(:pull_request_file_tree_visible)
    end

    # Check if the pull request file tree is 'available' for the current user,
    # based on whether the feature is enabled and the number of files in the diff.
    #
    # Returns Boolean
    def file_tree_available?(file_count:)
      return @file_tree_available if defined?(@file_tree_available)
      @file_tree_available = file_count.to_i > MIN_FILE_COUNT_FOR_FILE_TREE
    end

    def default_file_tree_hydro_payload(file_count:, pull_request_id:)
      return @default_file_tree_hydro_payload if defined?(@default_file_tree_hydro_payload)
      @default_file_tree_hydro_payload = {
        category: HYDRO_EVENT_CATEGORY,
        data: {
          file_count: file_count
        },
        pull_request_id: pull_request_id,
        user_id: T.unsafe(self).current_user&.id
      }
    end
  end
end
