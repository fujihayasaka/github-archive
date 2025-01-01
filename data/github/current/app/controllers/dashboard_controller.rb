# typed: true
# frozen_string_literal: true

class DashboardController < ApplicationController
  include DashboardAnalyticsHelper
  include DashboardHelper
  include Site::CustomerStoriesFeedHelper
  include ContextControllerMethods
  include ReactHelper

  layout "site", only: [:index], unless: :logged_in?

  around_action :switch_locale, only: [:index], unless: :logged_in?
  before_action :dotcom_required, only: :changelog
  before_action :check_email_verification, only: :index, if: :logged_in?
  before_action :clear_weak_password_session_variable, only: :index, unless: :logged_in?
  before_action :login_required, except: %w( index logged_out )
  before_action :add_csp_exceptions, only: :index
  before_action :enable_fullstory, only: [:index], unless: :logged_in?
  before_action :add_fullstory_csp_exceptions, only: [:index], unless: :logged_in?
  before_action :allow_youtube_csp_exception, only: [:index], unless: :logged_in?

  # needs investigation for protected organizations
  skip_before_action :perform_conditional_access_checks # rubocop:todo GitHub/DoNotSkipCapBeforeAction

  preload_features [:dashboard_favorites]

  javascript_bundle :"marketing-essentials", only: [:index], unless: :logged_in_or_enterprise?

  stylesheet_bundle :dashboard, :discussions, if: :logged_in_or_enterprise?
  stylesheet_bundle :site, :"landing-pages", :home, only: [:index], unless: :logged_in_or_enterprise?

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Ballast,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Authnd,
    ApplicationRecord::Repositories,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Configurations,
    ApplicationRecord::IssuesPullRequests,
    ApplicationRecord::Billing,
    ApplicationRecord::RepositoriesPushes,
    ApplicationRecord::Spokes,
    ApplicationRecord::Memex,
    only: [:index]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Configurations,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Ballast,
    ApplicationRecord::IssuesPullRequests,
    ApplicationRecord::Collab,
    ApplicationRecord::Repositories,
    only: [:ajax_your_teams]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Collab,
    ApplicationRecord::IssuesPullRequests,
    ApplicationRecord::Repositories,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Configurations,
    only: [:ajax_repositories]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Configurations,
    ApplicationRecord::IssuesPullRequests,
    ApplicationRecord::Repositories,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql5,
    ApplicationRecord::RepositoriesPushes,
    only: [:recent_activity]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Collab,
    ApplicationRecord::Repositories,
    ApplicationRecord::Mysql5,
    ApplicationRecord::IssuesPullRequests,
    ApplicationRecord::RepositoriesPushes,
    ApplicationRecord::IamAbilities,
    only: [:changelog]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql5,
    ApplicationRecord::IssuesPullRequests,
    ApplicationRecord::Repositories,
    ApplicationRecord::RepositoriesPushes,
    ApplicationRecord::Configurations,
    only: [:top_repositories]

  depends_on_clusters ApplicationRecord::Mysql1,
    only: [:logged_out]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Repositories,
    only: [:ajax_context_list]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Repositories,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::IamAbilities,
    only: [:trending_repositories]

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:ajax_context_list, :index], optional: true

  CSP_EXCEPTIONS = {
    img_src: [GitHub.asset_host_url, GitHub.og_image_generator_base_url],
    media_src: [GitHub.asset_host_url],
    connect_src: [GitHub.asset_host_url],
  }

  RECOMMENDATIONS_LIMIT = 20
  AJAX_REPOS_LIMIT = 100
  REPOS_LIMIT = 7
  YOUR_TEAMS_LIMIT = 7
  AJAX_YOUR_TEAMS_LIMIT = 100
  SAVED_NOTIFICATIONS_LIMIT = 4
  RECENT_ACTIVITY_LIMIT = 12
  TRENDING_REPOS_LIMIT = 3

  def index
    if logged_in?
      override_analytics_location "/dashboard"

      set_context
      context_region_title "Dashboard", path: home_url
      feed_topic = T.must(current_user).pinned_topics.where({ name: params[:topic] }).first if params[:topic].present?

      respond_to do |format|
        format.html do
          render "dashboard/index", layout: "layouts/dashboard_three_column", locals: {
            query: params[:q],
            feed_title: feed_topic.present? ? feed_topic.display_name : "Home",
            team_query: params[:team],
            teams: fetch_paginated_teams(per_page: YOUR_TEAMS_LIMIT, current_page_for_teams: current_page_for_teams),
            turbo_src: nil,
            explore_repos: explore_repos,
          }
        end
      end
    # SAML: If we redirect to login before there is a repository in
    # #enterprise_index, the idP may immediately authenticate the user again,
    # making it feel like no logout took place.
    elsif GitHub.single_or_multi_tenant_enterprise?
      enterprise_index
    else
      disable_color_modes
      # Homepage
      title = "GitHub · Build and ship software on a single, collaborative platform"
      header_classes = feature_enabled_globally_or_for_current_user?(:site_homepage_fixed_header) ? "header-overlay header-overlay-fixed js-header-overlay-fixed" : "header-overlay"

      render_react_app(
        app_name: "landing-pages",
        title: title,
        page_data: {
          class: header_classes,
          marketing_page_theme: "dark",
          richweb: {
            title: title,
            description: _("Join the world's most widely adopted, AI-powered developer platform where millions of developers, businesses, and the largest open source community build software that advances humanity."),
            url: T.must(request).original_url,
            image: image_path("modules/site/social-cards/home24.jpg"),
          },
        },
        ssr: true,
      )
    end
  end

  def top_repositories # rubocop:todo GitHub/UseRestfulActions
    render partial: "dashboard/top_repositories", locals: {
      query: params[:q],
      location: params[:location],
      repositories: fetch_top_repositories(page: 1, per_page: REPOS_LIMIT, initial_per_page: REPOS_LIMIT),
      viewer: current_user,
    }
  end

  def recent_activity # rubocop:todo GitHub/UseRestfulActions
    respond_to do |format|
      format.html do
        render Dashboard::RecentActivity::RecentActivityComponent.new(
          recent_interactions: fetch_recent_activity,
          mobile: params[:mobile].presence == "true"
        ), layout: false
      end
    end
  end

  def trending_repositories # rubocop:todo GitHub/UseRestfulActions
    return render_404 unless T.must(request).xhr?

    repositories = ExploreFeed::Trending::Repository.all.take(TRENDING_REPOS_LIMIT)
    respond_to do |format|
      format.html do
        render Dashboard::Sidebar::ExploreRepositoriesComponent.new(repositories: repositories), layout: false
      end
    end
  end

  def ajax_context_list # rubocop:todo GitHub/UseRestfulActions
    return render_404 unless T.must(request).xhr?

    context = User.find_by(login: params[:current_context])
    return render_404 unless context.present?

    respond_to do |format|
      format.any(:html, :html_fragment) do
        render Dashboard::ContextSwitcher::ListComponent.new(
          contexts: T.must(current_user).dashboard_contexts.contexts,
          current_context: context,
          id: params[:id]
        ), layout: false
      end
    end
  end

  def logged_out # rubocop:todo GitHub/UseRestfulActions
    if GitHub.enterprise?
      render "dashboard/logged_out", layout: "layouts/session_authentication"
    else
      render_404
    end
  end

  def ajax_repositories # rubocop:todo GitHub/UseRestfulActions
    if T.must(request).xhr?
      respond_to do |format|
        format.html do
          render partial: "dashboard/repositories", locals: {
            repositories: fetch_top_repositories(page: current_repos_page, per_page: AJAX_REPOS_LIMIT, initial_per_page: REPOS_LIMIT),
            user: current_user,
            query: params[:q],
            location: params[:location],
          }
        end
      end
    else
      redirect_to user_path(current_user, params: { tab: "repositories" })
    end
  end

  def ajax_your_teams # rubocop:todo GitHub/UseRestfulActions
    if T.must(request).xhr?
      respond_to do |format|
        format.html do
          render partial: "dashboard/teams", locals: {
            viewer: current_user,
            teams: fetch_paginated_teams(per_page: AJAX_YOUR_TEAMS_LIMIT, initial_per_page: YOUR_TEAMS_LIMIT, current_page_for_teams: current_page_for_teams),
            location: params[:location],
          }
        end
      end
    else
      redirect_to dashboard_path
    end
  end

  def ignore_upgrade # rubocop:todo GitHub/UseRestfulActions
    T.must(current_user).upgrade_ignore = T.must(current_user).plan.name
    T.must(current_user).save
    redirect_to action: "index"
  end

  def dismiss_bootcamp # rubocop:todo GitHub/UseRestfulActions
    T.must(current_user).dismiss_notice("bootcamp")

    if T.must(request).xhr?
      head :ok
    else
      redirect_to home_path
    end
  end

  def current_context # rubocop:todo GitHub/UseRestfulActions
    current_user
  end
  helper_method :current_context

  def changelog # rubocop:todo GitHub/UseRestfulActions
    render Dashboard::Sidebar::ChangelogComponent.new, layout: false
  end

  private

  def fetch_recent_activity
    unauthorized_account_ids = cap_filter.unauthorized_resource_ids(current_user&.resources_for_cap_filter)

    Issue::RecentInteractions.new(
      current_user,
      types: [:issue, :pull_request],
      since: 2.weeks.ago,
      organization_id: recent_activity_organization_id,
      excluded_account_ids: unauthorized_account_ids,
    ).fetch(limit: RECENT_ACTIVITY_LIMIT)
  end

  def recent_activity_organization_id
    return nil unless params[:organization_id].present?
    Platform::Helpers::NodeIdentification.from_global_id(params[:organization_id]).last&.to_i
  end

  # Non logged in user hitting home page under Enterprise. When the admin user
  # has already been created and at least one public repository exists, redirect
  # to the /repositories page so people can browse around. If no repositories
  # exist yet, redirect to the login page - there's nothing interesting to see
  # in that case. SAML is the exception because the idP may immediately
  # authenticate the user again, making it feel like no logout took place.
  def enterprise_index
    if GitHub.auth.saml? || GitHub.auth.github_oauth? || GitHub.auth.cas?
      render "dashboard/logged_out", layout: "layouts/session_authentication", locals: { index_page: true }
    elsif Repository.public_scope.first && (!GitHub.private_mode || logged_in?)
      redirect_to "/repositories"
    else
      redirect_to "/login"
    end
  end

  memoize def all_events
    events_timeline.events(page: 1, per_page: Stratocaster::DEFAULT_INDEX_SIZE)
  end

  def events_timeline_key
    "user:#{T.must(current_user).id}"
  end

  def ranked_repositories_since
    4.months.ago.iso8601
  end

  def check_email_verification
    return unless GitHub.email_verification_enabled?
    return unless T.must(current_user).should_verify_email?
    email = T.must(current_user).primary_user_email

    launch_code = if T.must(email).verification_token.present?
      T.must(email).launch_code_verification?
    else
      T.must(current_user).user?
    end

    # This logic can be removed once we fully ship the signup redesign, since
    # we should always send users to `account_verifications_path` once that's
    # done.
    if launch_code
      redirect_to account_verifications_path
    else
      redirect_to unverified_email_path
    end
  end

  def current_repos_page
    page = params[:repos_cursor].to_i
    page == 0 ? 1 : page
  end

  def current_page_for_teams
    page = params[:your_teams_cursor].to_i
    page == 0 ? 1 : page
  end

  def logged_in_or_enterprise?
    logged_in? || GitHub.single_or_multi_tenant_enterprise?
  end

  def allow_youtube_csp_exception
    youtube_csp_exceptions = {
      frame_src: ["https://www.youtube-nocookie.com"],
    }

    SecureHeaders.append_content_security_policy_directives(request, youtube_csp_exceptions)
  end

  def explore_repos
    return [] unless discover_repos_dashboard_enabled?

    repos = RepositoryRecommendation.filtered_for(current_user).sample(3)
    if repos.empty?
      RepositoryRecommendation
        .fetch_munger_fallback_recommendations(user: current_user, page: 1, per_page: 10)
        &.sample(3) || []
    else
      repos
    end
  end
end
