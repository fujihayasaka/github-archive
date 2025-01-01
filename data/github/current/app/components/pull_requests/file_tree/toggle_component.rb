# typed: true
# frozen_string_literal: true

module PullRequests
  module FileTree
    class ToggleComponent < ApplicationComponent

      SHOW_FILE_TREE_COPY = "Show file tree"
      HIDE_FILE_TREE_COPY = "Hide file tree"

      # Renders button that toggles the file tree open/closed.
      #
      # default_hydro_payload (optional) - Hash of Hydro click tracking data.
      #                                 See HydroHelper#hydro_click_tracking_attributes
      # split_diff (optional) - Boolean value for whether current diff view is "Split".
      #                       See DiffViewHelper#split_diff?
      # file_tree_visible (optional) - Boolean value for whether the user has specified to hide or show the
      #                             Pull Requests file tree.
      def initialize(default_hydro_payload: {}, split_diff: false, file_tree_visible: true, **system_arguments)
        @default_hydro_payload = default_hydro_payload
        @split_diff = split_diff
        @file_tree_visible = file_tree_visible
        @system_arguments = system_arguments
      end

      def hydro_data_attributes(action)
        hydro_payload = default_hydro_payload.merge(action: action)
        attributes = hydro_click_tracking_attributes("pull_request.user_action", hydro_payload)
        {
          # Use "hydro-click-payload" instead of "hydro-click" so this click event
          # is handled by `file-tree-element.ts` instead of `hydro-click-tracking.ts`
          "hydro-click-payload" => attributes["hydro-click"],
          "hydro-click-hmac" => attributes["hydro-click-hmac"]
        }
      end

      memoize def authenticity_token
        authenticity_token_for(update_url, method: "PUT")
      end

      memoize def update_url
        pr_file_tree_visibility_setting_path(user_id: current_user.display_login)
      end

      private

      attr_reader :default_hydro_payload, :split_diff, :file_tree_visible
    end
  end
end
