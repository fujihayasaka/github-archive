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
            repositories = find_repositories(count: JSON_ITEMS_MAX_COUNT)
            items = repositories.map do |repo|
              { value: repo.name_with_display_owner, url: repository_path(repo) }
            end
          when :teams
            teams = find_teams(count: JSON_ITEMS_MAX_COUNT)
            items = teams.map do |team|
              { value: team.combined_slug, url: team_path(team) }
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
        top_repos.select { |repo| repo.name_with_display_owner.downcase.include?(params[:q].downcase) }
      else
        fetch_top_repositories(page: page_param, per_page: ITEMS_PER_PAGE, initial_per_page: ITEMS_PER_PAGE)
      end
    end

    def find_teams(count: nil)
      if params[:q].present? || count
        top_teams = fetch_paginated_teams(per_page: count || max_items_count, current_page_for_teams: 1)
        top_teams.select { |team| team.combined_slug.downcase.include?(params[:q].downcase) }
      else
        fetch_paginated_teams(per_page: ITEMS_PER_PAGE, current_page_for_teams: page_param)
      end
    end

    def page_param
      params[:page].to_i
    end
  end
end
