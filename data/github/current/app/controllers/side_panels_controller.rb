# typed: true
# frozen_string_literal: true

class SidePanelsController < SidePanels::AbstractController
  include DashboardHelper
  include GitHub::Memoizer
  include UsersHelper
  include DashboardSidebarHelper

  ACTIONS_EXCLUDED_FROM_CAP_IP_ALLOWLIST_POLICY = %w(show)

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Collab

  # Optional clusters
  depends_on_clusters ApplicationRecord::Ballast,
    ApplicationRecord::Configurations,
    ApplicationRecord::Copilot,
    ApplicationRecord::Iam,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::IssuesPullRequests,
    ApplicationRecord::Memex,
    ApplicationRecord::Mysql2,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Notify,
    ApplicationRecord::Repositories,
    ApplicationRecord::Spokes,
    ApplicationRecord::NotificationsEntries,
    optional: true

  def show
    if panel == :global
      with_database_error_fallback(fallback: -> { render_global_panel(fallback: true) }) do
        render_global_panel
      end
    elsif panel == :user
      with_database_error_fallback(fallback: -> { render_user_panel(fallback: true) }) do
        render_user_panel
      end
    else
      render_404
    end
  end

  private

  def ip_allowlist_enforceable
    return :no if ACTIONS_EXCLUDED_FROM_CAP_IP_ALLOWLIST_POLICY.include?(action_name)
    super
  end

  def external_conditional_access_policy_enforceable
    return :no if ACTIONS_EXCLUDED_FROM_CAP_IP_ALLOWLIST_POLICY.include?(action_name)
    super
  end

  def render_global_panel(fallback: false)
    repos = []
    teams = []
    pinned_repos = []

    if !fallback
      repos = fetch_top_repositories(page: 1, per_page: ITEMS_PER_PAGE, initial_per_page: ITEMS_PER_PAGE)
      teams = current_user.feature_flag_enabled?(:global_nav_react_teams_settings_page, default: false) ? [] : fetch_paginated_teams(per_page: ITEMS_PER_PAGE, current_page_for_teams: 1)
      # UserDashboardPin limits to 25 pinned items per user
      pinned_repos = authorized_pinned_repositories if include_pinned_repos?
    end

    respond_to do |format|
      format.html do
        render Site::Header::GlobalSidePanelComponent.new(
          load_everything: true,
          rich_content_enabled: !fallback,
          repositories: repos,
          teams: teams,
          items_per_page: ITEMS_PER_PAGE,
          max_pages: MAX_PAGES,
          cookie_consent_enabled: @cookie_consent_enabled,
        ), layout: false
      end
      format.json do
        return render_404 unless current_user.feature_flag_enabled?(:global_nav_react_menu, default: false)

        render json: {
          repositories: repos.map do |repo|
            {
              value: repo.name_with_display_owner,
              url: repository_path(repo),
              avatar_url: repo.owner.primary_avatar_url
            }
          end,
          teams: teams.map do |team|
            {
              value: team.combined_slug,
              url: team_path(team),
              avatar_url: team.owner.primary_avatar_url
            }
          end,
          pinned_items: {
            repositories: pinned_repos.map do |repo|
              {
                value: repo.name_with_display_owner,
                url: repository_path(repo),
                avatar_url: repo.owner.primary_avatar_url
              }
            end
          }
        }
      end
    end
  end

  sig { returns(T::Array[Hash]) }
  memoize def get_user_sso_enabled_organizations
    unauthorized_accounts = cap_filter.unauthorized(current_user&.resources_for_cap_filter).by_policy
    unauthorized_saml_accounts = unauthorized_accounts[:saml] || []

    current_user.organizations.select(&:saml_sso_present?).map do |org|
      {
        sso_url: "/orgs/#{org.name}/sso",
        needs_authentication: unauthorized_saml_accounts.include?(org),
      }
    end
  end

  sig { returns(T::Boolean) }
  def show_sso?
    get_user_sso_enabled_organizations.any?
  end

  sig { returns(T::nilable(String)) }
  def sso_url
    return unless show_sso?

    sso_orgs = get_user_sso_enabled_organizations

    if sso_orgs.size == 1
      first_org = T.must(sso_orgs.first)
      return first_org[:sso_url] if first_org[:needs_authentication]
    end

    "/settings/organizations"
  end

  def render_user_panel(fallback: false)
    if fallback
      return respond_to do |format|
        format.html do
          render Site::Header::UserDrawerSidePanelComponent.new(load_everything: false), layout: false
        end

        format.json do
          render "side_panels/show"
        end
      end
    end

    repo = if params[:repository_id].present?
      if FeatureFlag.vexi.enabled?(:repos_domain_find_by, default: false)
        T.cast(Repositories.domain.by_id(params[:repository_id].to_i), T.nilable(Repository)) # rubocop:todo GitHub/AvoidCast
      else
        Repository.find_by(id: params[:repository_id])
      end
    end
    current_repository = repo if repo&.readable_by?(current_user)

    show_teams = FeatureFlag.vexi.enabled?(:global_nav_react_teams_settings_page, current_user, default: false) && current_user.teams.any?

    respond_to do |format|
      format.html do
        render Site::Header::UserDrawerSidePanelComponent.new(
          load_everything: true,
          user_can_create_organizations: user_can_create_organizations?,
          repository: current_repository,
          memex_enabled: GitHub.projects_new_enabled?,
          account_switcher_helper: account_switcher_helper,
          user: current_user,
          has_unseen_features: current_user.new_prerelease_features?,
        ), layout: false
      end

      format.json do
        render "side_panels/show", locals: {
          show_enterprise_trial: show_enterprise_trial?,
          stashed_accounts: stashed_accounts,
          show_sso: show_sso?,
          sso_url: sso_url,
          show_teams: show_teams,
          teams_url: show_teams ? settings_teams_url : nil,
        }
      end
    end
  end

  def show_enterprise_trial?
    return false if GitHub.enterprise?
    return false if current_user.is_enterprise_managed?
    return false if current_user.businesses(membership_type: :admin).any?
    return false if current_user.owned_organizations.where(plan: GitHub::Plan.business_plus.name).any?
    true
  end

  StashedAccount = T.type_alias do
    {
      login: String,
      name: T.nilable(String),
      avatarUrl: String,
      userSessionId: T.nilable(Integer),
    }
  end
  sig { returns(T::Array[StashedAccount]) }
  def stashed_accounts
    account_switcher_helper.stashed_accounts.all.map do |account|
      {
        login: account.user.display_login,
        name: account.user.profile_name,
        avatarUrl: account.user.primary_avatar_url,
        userSessionId: account.user_session&.id,
      }
    end
  end

  sig { returns(T::Boolean) }
  def include_pinned_repos?
    current_user.feature_flag_enabled?(:global_nav_react_sidebar_pinned_repos, default: false) &&
    current_user.feature_flag_enabled?(:global_nav_react_menu, default: false)
  end
end
