# typed: true
# frozen_string_literal: true

module SidePanels
  class ItemsController < AbstractController
    include DashboardHelper
    include DashboardSidebarHelper

    depends_on_clusters ApplicationRecord::Ballast,
      ApplicationRecord::Collab,
      ApplicationRecord::Configurations,
      ApplicationRecord::Iam,
      ApplicationRecord::IamAbilities,
      ApplicationRecord::IssuesPullRequests,
      ApplicationRecord::Mysql1,
      ApplicationRecord::Mysql5,
      ApplicationRecord::Repositories

    depends_on_clusters ApplicationRecord::Profiles,
      only: [:index]

    depends_on_clusters ApplicationRecord::Memex,
      ApplicationRecord::Mysql2,
      ApplicationRecord::Spokes,
      ApplicationRecord::NotificationsEntries,
      optional: true

    def index
      item_type = params[:type].to_sym

      return render_404 unless item_type == :repositories

      repositories = find_repositories

      items = repositories.map do |repo|
        {
          id: repo.id,
          value: repo.name_with_display_owner,
          url: repository_path(repo),
          avatar_url: repo.owner.primary_avatar_url,
          has_more: repositories.has_more?
        }
      end

      render json: items
    end

    private

    def find_repositories(count: nil)
      if params[:q].present? || count
        top_repos = TopRepositories.paginated_for(
          viewer: current_user,
          cap_filter: cap_filter,
          per_page: count || max_items_count,
          initial_per_page: count || max_items_count,
        )

        if params[:q].present?
          filtered = top_repos.class.new(
            page: top_repos.current_page,
            per_page: top_repos.per_page,
            has_more: top_repos.has_more?
          )
          filtered.concat(
            top_repos.select { |repo| repo.name_with_display_owner.downcase.include?(params[:q].downcase) }
          )
          filtered
        else
          top_repos
        end
      else
        TopRepositories.paginated_for(
          viewer: current_user,
          cap_filter: cap_filter,
          page: page_param,
          per_page: items_per_page,
          initial_per_page: initial_items_per_page,
        )
      end
    end

    def page_param
      params[:page].to_i
    end
  end
end
