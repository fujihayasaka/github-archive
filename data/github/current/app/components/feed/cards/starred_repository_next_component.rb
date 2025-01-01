# typed: true
# frozen_string_literal: true

module Feed
  module Cards
    class StarredRepositoryNextComponent < RepoBaseComponent
      HEADING_ICON = { name: :"feed-star", color: :attention }.freeze

      private

      def heading_icon
        HEADING_ICON
      end

      def subject_heading
        if item.rollup?
          "#{item.total_related_items + 1} #{multiple_repository_heading}"
        else
          single_repository_heading
        end
      end

      def multiple_repository_heading
        if owner_is_viewer? && Flipper[:conduit_starred_viewer_repo].enabled?(item.viewer)
          "of your repositories"
        else
          "repositories"
        end
      end

      def single_repository_heading
        if owner_is_viewer? && Flipper[:conduit_starred_viewer_repo].enabled?(item.viewer)
          "your repository"
        else
          "a repository"
        end
      end
    end
  end
end
