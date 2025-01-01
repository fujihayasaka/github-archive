# typed: true
# frozen_string_literal: true

module Feed
  module Cards
    class ForkedRepositoryNextComponent < RepoBaseComponent
      HEADING_ICON = { name: :"feed-forked", color: :muted }.freeze

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
        if Flipper[:conduit_forked_viewer_repo].enabled?(item.viewer) && parent_owner_is_viewer?
          "of your repositories"
        else
          "repositories"
        end
      end

      def single_repository_heading
        if Flipper[:conduit_forked_viewer_repo].enabled?(item.viewer) && parent_owner_is_viewer?
          "your repository"
        else
          "a repository"
        end
      end
    end
  end
end
