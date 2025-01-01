# typed: true
# frozen_string_literal: true


class SidePanelsController < SidePanels::AbstractController
  extend T::Sig
  include DashboardHelper
  include GitHub::Memoizer
  include UsersHelper

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

  def render_global_panel(fallback: false)
    repos = []
    teams = []
    orgs_needing_sso = []

    if !fallback
      repos = fetch_top_repositories(page: 1, per_page: ITEMS_PER_PAGE, initial_per_page: ITEMS_PER_PAGE)
      teams = fetch_paginated_teams(per_page: ITEMS_PER_PAGE, current_page_for_teams: 1)

      # todo: only consider orgs that contain repositories within the user's Top Repos / Top Teams
      # to prevent unnecessary SSO notices for irrelevant SAML orgs that the user is a member of
      # https://github.com/github/platform-ux/issues/1291
      orgs = current_user.organizations
      unauthorized_orgs = cap_filter.unauthorized(orgs).by_policy
      orgs_needing_sso = unauthorized_orgs[:saml] || []
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
          orgs_needing_sso: orgs_needing_sso,
          cookie_consent_enabled: @cookie_consent_enabled,
        ), layout: false
      end
    end
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

    repo = Repository.find_by(id: params[:repository_id]) if params[:repository_id].present?
    current_repository = repo if repo&.readable_by?(current_user)

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
          stashed_accounts: stashed_accounts
        }
      end
    end
  end

  def show_enterprise_trial?
    return false if GitHub.enterprise?
    return false if current_user.is_enterprise_managed?
    return false if current_user.businesses(membership_type: :admin).count > 0
    return false if current_user.owned_organizations.where(plan: GitHub::Plan.business_plus.name).count > 0
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
end
