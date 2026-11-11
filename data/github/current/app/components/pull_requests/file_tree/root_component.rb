# typed: true
# frozen_string_literal: true

module PullRequests
  module FileTree
    class RootComponent < ApplicationComponent
      attr_reader :tree, :file_types, :codeowners, :default_hydro_payload

      PATHNAME_FILTER_HYDRO_CATEGORY = "file_filter"
      PATHNAME_FILTER_HYDRO_ACTION = "filter_by_pathname"

      # All ocitcon icon names used by this component or its children.
      # Used to generate a spritesheet.
      ICONS = (
        %w[
         file-directory-fill
         file-submodule
         file
         chevron-down
        ] + PullRequests::FileTree::NodeComponent::STATUS_ICONS.map { |_, attrs| attrs.fetch(:icon) }
      ).map { |icon| { symbol: icon }.freeze }.freeze

      # The parent component for a file tree, which builds a tree representation
      # of the given diff and renders a collection of child components, where
      # each child is a PullRequests::FileTree::NodeComponent.
      #
      # diff - An instance of GitHub::Diff
      # viewed_files (optional) - An instance of PullRequestUserReviews
      # codeowners (optional) - An instance of Repository::Codeowners
      # default_hydro_payload (optional) - Hash of Hydro click tracking data.
      #                                 See HydroHelper#hydro_click_tracking_attributes
      def initialize(diff, default_hydro_payload: {}, viewed_files: nil, codeowners: nil)
        @tree = diff.to_tree
        @codeowners = codeowners
        @default_hydro_payload = default_hydro_payload
        @file_types = diff.file_types
        @viewed_files = viewed_files
      end

      def pathname_filter_hydro_tracking_attributes
        hydro_payload = default_hydro_payload.merge(
          action: PATHNAME_FILTER_HYDRO_ACTION,
          category: PATHNAME_FILTER_HYDRO_CATEGORY
        )
        attributes = hydro_click_tracking_attributes(FileTreeHelper::HYDRO_EVENT, hydro_payload)

        # Use "hydro-click-payload" instead of "hydro-click" so this click event
        # is handled by `file-tree-element.ts` instead of `hydro-click-tracking.ts`
        <<~HTML.strip
          data-hydro-click-payload=#{attributes["hydro-click"]}
          data-hydro-click-hmac=#{attributes["hydro-click-hmac"]}
        HTML
      end

      private

      attr_reader :viewed_files
    end
  end
end
