# typed: false
# frozen_string_literal: true

module DashboardHelper
  GH_FOR_VSCODE_EXTENSION_ID = 797352.freeze
  TRENDING_REPOSITORY_EXP_ID = "Fe1445".freeze
  DEFAULT_PULLS_DEFAULT_VIEW = "inbox".freeze
  PULLS_DEFAULT_VIEW_OPTIONS = %w(inbox authored assigned involves reviews on-my-behalf).freeze
  PULLS_DEFAULT_VIEW_COOKIE = "dashboard_surface_pulls_default_view".freeze

  def feed_has_only_one_page_of_events?
    return false if current_page > 1
    event_count < Stratocaster::DEFAULT_PAGE_SIZE
  end

  def display_private_repo_limit_banner?
    return false unless logged_in?

    !current_user.ignored_upgrade? && current_user.at_plan_repo_limit? && !current_user.disabled?
  end

  def display_copilot_snippy_warning?
    return false unless logged_in?

    with_database_error_fallback(fallback: false) do
      current_copilot_user.can_modify_copilot_settings? && !current_copilot_user.public_code_suggestions_configured? &&
      !current_copilot_user.is_enterprise_managed?
    end
  end

  def display_copilot_trial_warning?
    return false unless logged_in?

    copilot_days_left_on_trial > 0 && copilot_days_left_on_trial <= 3
  end

  def copilot_days_left_on_trial
    return -1 unless logged_in?

    current_copilot_user.days_left_on_trial
  end

  def copilot_business_trial
    return unless logged_in?

    org_ids = current_user.owned_organizations.map do |org|
      org[:id]
    end

    with_database_error_fallback { Copilot::BusinessTrial.find_by(trialable_id: org_ids) }
  end

  def display_org_private_repo_limit_banner?
    org_admin? && !current_organization.ignored_upgrade? &&
      current_organization.at_plan_repo_limit? && !current_organization.disabled?
  end

  # Public: Returns true if the current user can change to another context on their dashboard.
  # This happens when a user belongs to an organization.
  def user_can_switch_contexts?
    current_user.dashboard_contexts.switchable?
  end

  # Public: True if the profile readme should be rendered
  #         for this viewer
  def show_profile_navigation?
    return false unless logged_in?
    current_user.profile_navigation_visible?
  end

  # Is the user a billing manager for the supplied orgs?
  #
  # Returns a Boolean.
  def user_is_billing_manager?(user, orgs)
    orgs.any? do |org|
      org.billing_manager_only?(user)
    end
  end

  def dashboard_news_feed_next_page_path
    if current_organization
      org_dashboard_path(current_organization, page: current_page + 1)
    else
      dashboard_news_feed_path(page: current_page + 1)
    end
  end

  def render_org_welcome
    if org_admin?
      render partial: "organizations/welcome_owner", locals: { org: current_organization }
    else
      render partial: "organizations/welcome", locals: { org: current_organization }
    end
  end

  TEACHER_ROLE_SHORT_TEXT = "role_teacher"
  STUDENT_ROLE_SHORT_TEXT = "role_student"

  def show_existing_user_github_education_banner?
    @show_github_education_banner = !dismissed_github_education_banner? && current_user.student_developer_pack_coupon?
  end

  def user_has_global_campus_dashboard_notice?
    return false unless FeatureFlag.vexi.enabled?(:global_campus_dashboard_notice, current_user, default: false)

    current_user.notices_for_dashboard.include?(UserNotice::DASHBOARD_GLOBAL_CAMPUS_NOTICE)
  end

  def show_new_user_github_education_banner?
    @show_github_education_banner = !dismissed_github_education_banner? && !current_user.student_developer_pack_coupon? &&
    (edu_email_eligible? || user_has_global_campus_dashboard_notice?)
  end

  def dismissed_github_education_banner?
    return true if current_user.dismissed_notice?(UserNotice::DASHBOARD_GLOBAL_CAMPUS_NOTICE)
    false
  end

  def fetch_paginated_teams(per_page:, initial_per_page: nil, current_page_for_teams: nil)
    visibility_scope = current_user.
      async_visible_teams_for(current_user).
      sync

    cap_authorized_team_ids = cap_filter.authorized_resource_ids(visibility_scope)

    Team.ranked_for(current_user, scope: visibility_scope).
      where(id: cap_authorized_team_ids).
      includes(:organization).
      simple_paginate(per_page: per_page, page: current_page_for_teams, initial_per_page: initial_per_page)
  end

  # Public: check if the Dashboard for GitHub Universe 2025 is enabled for user.
  #
  # Returns Boolean
  def dashboard_universe_enabled?
    return @dashboard_universe_enabled if instance_variable_defined?(:@dashboard_universe_enabled)
    return false unless logged_in?

    # Check if the user has enrolled themselves in the preview, or if they are
    # enrolled by default via the feature flag override.
    @dashboard_universe_enabled = current_user.feature_preview_enabled?(
      :dashboard_universe_2025,
      enrolled_by_default_override: FeatureFlag.vexi.enabled?(:dashboard_universe_2025_default, current_user, default: false)
    )
  end

  # Public: check if the React pull requests dashboard is enabled for user.
  #
  # Uses the Feature Preview system with the `dashboard_surface_react_app`
  # feature preview as the source of truth. Users may be enrolled by default
  # when the opt-out-by-default feature flag is enabled for them.
  #
  # Returns Boolean
  def dashboard_surface_react_app_enabled?
    return @dashboard_surface_react_app_enabled if instance_variable_defined?(:@dashboard_surface_react_app_enabled)
    return false unless logged_in?

    @dashboard_surface_react_app_enabled = current_user.feature_preview_enabled?(
      :dashboard_surface_react_app,
      enrolled_by_default_override: FeatureFlag.vexi.enabled?(:dashboard_surface_react_app_opt_out_by_default, current_user, default: false)
    )
  end

  # Public: default pulls view for user.
  #
  # Reads from a cookie value, or falls back to the default pulls view. The
  # cookie value may be either a known view slug (see
  # PULLS_DEFAULT_VIEW_OPTIONS) or the stringified id of one of the user's
  # saved views (a SearchShortcut). When it points at a saved view that no
  # longer exists or is not owned by the current user, the default falls
  # back to DEFAULT_PULLS_DEFAULT_VIEW.
  #
  # Returns String
  sig { returns(String) }
  def get_pulls_default_view
    return DEFAULT_PULLS_DEFAULT_VIEW unless current_user

    pulls_default_view_from_cookie
  rescue => e
    GitHub.logger.warn("Failed to load pulls default view setting: #{e.message}")
    GitHub.dogstats.increment("dashboard_surface.pulls_default_view_setting.failed", tags: ["surface"])
    DEFAULT_PULLS_DEFAULT_VIEW
  end

  sig { params(pr_ids: T::Array[Integer]).returns(T::Array[Issue]) }
  def load_authorized_issues_from_pr_ids(pr_ids)
    user = current_user
    return [] if pr_ids.empty? || user.nil?

    issue_ids = Issue.where(pull_request_id: pr_ids).pluck(:id)
    return [] if issue_ids.empty?

    visible_ids = Issue.legacy_visible_ids_for(issue_ids, viewer: user)
    Issue.where(id: visible_ids).to_a
  end

  private

  sig { returns(String) }
  def pulls_default_view_from_cookie
    cookie_value = request&.cookies&.[](PULLS_DEFAULT_VIEW_COOKIE)
    return DEFAULT_PULLS_DEFAULT_VIEW unless cookie_value.present?
    return cookie_value if PULLS_DEFAULT_VIEW_OPTIONS.include?(cookie_value)
    return cookie_value if valid_saved_view?(cookie_value)

    DEFAULT_PULLS_DEFAULT_VIEW
  end

  # Returns true when the value is the stringified id of a pull-requests
  # saved view (SearchShortcut) owned by the current user.
  sig { params(value: String).returns(T::Boolean) }
  def valid_saved_view?(value)
    return false unless value.match?(/\A\d+\z/)

    saved_view_id = value.to_i
    dashboard = current_user&.dashboard
    return false unless dashboard

    dashboard&.shortcuts&.where(search_type: DashboardSurface::Loaders::SavedViewLoader::SearchType::PullRequests.serialize, id: saved_view_id)&.exists?
  end

  def edu_email_eligible?
    @edu_email_eligible = current_user.edu_email?
  end

  def url_for_feed(query_params = {})
    opt_out = params[:opt_out_conduit_cache] == "true" && user_feature_enabled?(:feeds_conduit_cache_opt_out)

    if opt_out
      query_params[:opt_out_conduit_cache] = true
    end

    if params[:org] && GitHub.conduit_enabled?(user: current_user)
      query_params[:org] = params[:org]
      conduit_org_feeds_path(params: query_params)
    else
      conduit_for_you_feed_path(params: query_params)
    end
  end

  # Returns an ES routing string of the viewer's active repository IDs,
  # or nil if the feature is disabled, the set exceeds the cap, or
  # computation fails. Used by pulls dashboard surfaces to reduce shard fanout.
  def active_repo_routing_for(user)
    return nil unless FeatureFlag.vexi.enabled?(:dashboard_surface_active_repo_routing, user, default: false)

    client = PullRequests::Cache::ActiveReposClient.new(current_user: user)
    repo_ids = client.fetch { compute_active_repo_ids(user) }

    return nil if repo_ids.blank? || repo_ids.length > PullRequests::Cache::ActiveReposClient::MAX_REPO_IDS

    repo_ids.join(",")
  rescue => e
    GitHub.dogstats.increment("dashboard_surface.active_repo_routing.error")
    GitHub.logger.warn("active_repo_routing_for failed: #{e.message}")
    nil
  end

  # Computes the distinct repo IDs the user has touched via PRs in the last 30 days.
  # Includes repos where the user authored PRs OR was requested as a reviewer.
  private def compute_active_repo_ids(user)
    authored_repo_ids = Issue.where(
      user_id: user.id,
      pull_request: true,
    ).where("issues.updated_at > ?", 30.days.ago)
      .distinct
      .pluck(:repository_id)

    reviewed_repo_ids = ReviewRequest.where(
      reviewer_type: "User",
      reviewer_id: user.id,
    ).where("review_requests.created_at > ?", 30.days.ago)
      .distinct
      .pluck(:repository_id)

    authored_repo_ids.concat(reviewed_repo_ids).uniq.first(PullRequests::Cache::ActiveReposClient::MAX_REPO_IDS + 1)
  end
end
