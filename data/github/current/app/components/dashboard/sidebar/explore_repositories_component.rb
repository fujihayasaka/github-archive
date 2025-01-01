# typed: true
# frozen_string_literal: true

module Dashboard
  module Sidebar
    class ExploreRepositoriesComponent < ApplicationComponent
      attr_reader :repositories

      def initialize(repositories:)
        @repositories = repositories
      end

      def render?
        return false if GitHub.multi_tenant_enterprise?
        repositories.any?
      end

      def see_more_url
        {
          href: explore_path,
          data: helpers.discover_repositories_explore_attributes,
          test_selector: "explore_repo_explore_more"
        }
      end

      memoize def section_title
        "Explore repositories"
      end

      def hydro_event_data(repo_id: nil, target: nil)
        helpers.discover_repositories_attributes(repo_id, target)
      end

      def starred_by_viewer
        if logged_in?
          trending_repo_ids = repositories.map(&:id)

          if GitHub.flipper[:stars_domain_explore].enabled?(current_user)
            current_user.starred_repository_ids(repo_ids: trending_repo_ids).to_set
          else
            current_user.stars.for_repository(trending_repo_ids).pluck(:starrable_id).to_set
          end
        else
          Set.new
        end
      end

    end
  end
end
