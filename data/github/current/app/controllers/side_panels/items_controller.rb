# typed: true
# frozen_string_literal: true

module SidePanels
  class ItemsController < AbstractController
    include DashboardHelper
    include DashboardSidebarHelper

    depends_on_clusters ApplicationRecord::Ballast,
      ApplicationRecord::Collab,
      ApplicationRecord::Configurations,
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
      ApplicationRecord::Iam,
      ApplicationRecord::NotificationsEntries,
      optional: true

    JSON_ITEMS_MAX_COUNT = 20

    def index
      item_type = params[:type].to_sym

      allowed_item_types = [:repositories, :teams]
      allowed_item_types << :pinned_items if react_menu_enabled? && pinned_items_enabled?

      return render_404 unless allowed_item_types.include?(item_type)

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
            if react_menu_enabled?
              repositories = find_repositories
            else
              repositories = find_repositories(count: JSON_ITEMS_MAX_COUNT)
            end

            items = repositories.map do |repo|
              {
                id: repo.id,
                value: repo.name_with_display_owner,
                url: repository_path(repo),
                avatar_url: react_menu_enabled? ? repo.owner.primary_avatar_url : nil,
                has_more: repositories.has_more?
              }
            end
          when :teams
            if react_menu_enabled?
              teams = find_teams
            else
              teams = find_teams(count: JSON_ITEMS_MAX_COUNT)
            end

            items = teams.map do |team|
              {
                id: team.id,
                value: team.combined_slug,
                url: team_path(team),
                avatar_url: react_menu_enabled? ? team.owner.primary_avatar_url : nil,
                has_more: teams.has_more?
              }
            end
          when :pinned_items
            items = find_pinned_items.map do |repo|
              {
                id: repo.id,
                value: repo.name_with_display_owner,
                url: repository_path(repo),
                avatar_url: repo.owner.primary_avatar_url
              }
            end
            # Return items in the shape expected by the SelectPickerDialog component we use to search pinned items
            # https://github.com/github/github-ui/blob/d0f94dcb431f937bc203c37c8a4f0b6f25db6193/packages/filter-picker/SelectPickerDialog.tsx#L54
            items = { items: items }
          end
          render json: items
        end
      end
    end

    private

    def find_pinned_items
      # We currently only support pinned repositories in the React sidebar, but this may change in the future
      fetch_pinnable_repositories(params[:q], items_per_page: max_items_count)
    end

    def find_repositories(count: nil)
      if params[:q].present? || count
        top_repos = fetch_top_repositories(page: 1, per_page: count || max_items_count, initial_per_page: count || max_items_count)

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
        if FeatureFlag.vexi.enabled?(:initial_per_page_pagination_updates, default: false)
          fetch_top_repositories(page: page_param, per_page: items_per_page, initial_per_page: initial_items_per_page)
        else
          fetch_top_repositories(page: page_param, per_page: items_per_page, initial_per_page: items_per_page)
        end
      end
    end

    def find_teams(count: nil)
      if params[:q].present? || count
        top_teams = fetch_paginated_teams(per_page: count || max_items_count, current_page_for_teams: 1)

        if params[:q].present?
          filtered = top_teams.class.new(
            page: top_teams.current_page,
            per_page: top_teams.per_page,
            has_more: top_teams.has_more?
          )
          filtered.concat(
            top_teams.select { |team| team.combined_slug.downcase.include?(params[:q].downcase) }
          )
          filtered
        else
          top_teams
        end
      else
        fetch_paginated_teams(per_page: items_per_page, current_page_for_teams: page_param)
      end
    end

    def page_param
      params[:page].to_i
    end

    sig { returns(T::Boolean) }
    def react_menu_enabled?
      current_user.feature_flag_enabled?(:global_nav_react, default: false) ||
      current_user.feature_flag_enabled?(:global_nav_react_menu, default: false) ||
      (dashboard_universe_enabled? &&
        !current_user.feature_flag_enabled?(:disable_dashboard_repositories, default: false))
    end

    sig { returns(T::Boolean) }
    def pinned_items_enabled?
      current_user.feature_flag_enabled?(:global_nav_react_sidebar_pinned_repos, default: false)
    end
  end
end
