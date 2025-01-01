# typed: true
# frozen_string_literal: true

module SidePanels
  class ItemsController < AbstractController
    include DashboardHelper

    depends_on_clusters ApplicationRecord::Ballast,
      ApplicationRecord::Collab,
      ApplicationRecord::Configurations,
      ApplicationRecord::IamAbilities,
      ApplicationRecord::IssuesPullRequests,
      ApplicationRecord::Mysql1,
      ApplicationRecord::Mysql5,
      ApplicationRecord::Repositories

    depends_on_clusters ApplicationRecord::Memex,
      ApplicationRecord::Mysql2,
      ApplicationRecord::Spokes,
      optional: true

    JSON_ITEMS_MAX_COUNT = 20

    def index
      item_type = params[:type].to_sym

      return render_404 unless [:repositories, :teams].include?(item_type)

      respond_to do |format|
        format.html do
          if item_type == :repositories
            render partial: "side_panels/items/repositories", layout: false, locals: {
              repositories: find_repositories
            }
          elsif item_type == :teams
            render partial: "side_panels/items/teams", layout: false, locals: {
              teams: find_teams
            }
          end
        end
        format.json do
          case item_type
          when :repositories
            if current_user.feature_flag_enabled?(:global_nav_react_menu, default: false)
              repositories = find_repositories
            else
              repositories = find_repositories(count: JSON_ITEMS_MAX_COUNT)
            end

            items = repositories.map do |repo|
              {
                value: repo.name_with_display_owner,
                url: repository_path(repo),
                avatar_url: current_user.feature_flag_enabled?(:global_nav_react_menu, default: false) ? repo.owner.primary_avatar_url : nil
              }
            end
          when :teams
            if current_user.feature_flag_enabled?(:global_nav_react_menu, default: false)
              teams = find_teams
            else
              teams = find_teams(count: JSON_ITEMS_MAX_COUNT)
            end

            items = teams.map do |team|
              {
                value: team.combined_slug,
                url: team_path(team),
                avatar_url: current_user.feature_flag_enabled?(:global_nav_react_menu, default: false) ? team.owner.primary_avatar_url : nil
              }
            end
          end
          render json: items
        end
      end
    end

    private

    def find_repositories(count: nil)
      if params[:q].present? || count
        top_repos = fetch_top_repositories(page: 1, per_page: count || max_items_count, initial_per_page: count || max_items_count)

        if params[:q].present?
          top_repos.select { |repo| repo.name_with_display_owner.downcase.include?(params[:q].downcase) }
        else
          top_repos
        end
      else
        fetch_top_repositories(page: page_param, per_page: ITEMS_PER_PAGE, initial_per_page: ITEMS_PER_PAGE)
      end
    end

    def find_teams(count: nil)
      if params[:q].present? || count
        top_teams = fetch_paginated_teams(per_page: count || max_items_count, current_page_for_teams: 1)

        if params[:q].present?
          top_teams.select { |team| team.combined_slug.downcase.include?(params[:q].downcase) }
        else
          top_teams
        end
      else
        fetch_paginated_teams(per_page: ITEMS_PER_PAGE, current_page_for_teams: page_param)
      end
    end

    def page_param
      params[:page].to_i
    end
  end
end
