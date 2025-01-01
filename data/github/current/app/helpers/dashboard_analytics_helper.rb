# typed: true
# frozen_string_literal: true

module DashboardAnalyticsHelper
  extend T::Sig
  extend T::Helpers
  include HydroHelper

  abstract!

  sig { abstract.returns(T.untyped) }
  def current_user; end

  sig { abstract.returns(T.untyped) }
  def current_context; end

  DASHBOARD_VERSION = 2

  module ::Dashboard
    module EventContext
      NEW_USER_BANNER = :NEW_USER_BANNER
      EMPTY_FEED = :EMPTY_FEED
      ORGANIZATIONS = :ORGANIZATIONS
      DISCOVER_REPOSITORIES = :DISCOVER_REPOSITORIES
      INLINE_RENDER = :INLINE_RENDER
      GET_STARTED = :GET_STARTED

      module Sidebar
        REPOSITORIES     = :REPOSITORIES
        SHORTCUTS        = :SHORTCUTS
        FAVORITES        = :FAVORITES
        TEAMS            = :TEAMS
        RECENT_ACTIVITY  = :RECENT_ACTIVITY
        ACCOUNT_SWITCHER = :ACCOUNT_SWITCHER
        CONTRIBUTED_REPOSITORIES = :CONTRIBUTED_REPOSITORIES
        BROADCAST = :BROADCAST
        TRENDING_REPOSITORIES = :TRENDING_REPOSITORIES
      end
    end
  end

  # Internal: Log dashboard.discovery_feed event
  #
  # user - a User
  # analytics_hash - a Hash of additional tracking dimensions (default: {})
  #   currently_starred_repos_count - number of repos starred by the viewer
  #   currently_following_users_count - number of users viewer is following
  #   events_shown: true if any feed events are shown
  #   banner_shown: true if a top level banner is shown
  #   banner_dismissable: true if a top level banner is shown and dismissable
  #   page_type: the page type ("activity" or "discover")
  #
  # Returns nothing
  def instrument_dashboard_page_view(user, payload:)
    GlobalInstrumenter.instrument("dashboard.page_view", payload.merge(
      dashboard_version: DASHBOARD_VERSION,
      user: user,
    ))
  end

  # Provide a wrapper around the standard dashboard parameters sent to hydro for analytics
  #
  # event_context - symbol representing the context for the event to be sent to hydro
  # target -  symbol representing the event
  #
  # Returns a Hash
  def dashboard_hydro_click_tracking_attributes(event_context:, target:)
    context = current_context.class.to_s.downcase

    hydro_click_tracking_attributes(
      "dashboard.click",
      event_context: event_context,
      dashboard_context: context,
      dashboard_version: DASHBOARD_VERSION,
      target: target,
      user_id: current_user&.id,
    )
  end

  def dashboard_empty_feed_watch_data_attributes(analytics_dimensions)
    dashboard_hydro_click_tracking_attributes(
      event_context: Dashboard::EventContext::EMPTY_FEED,
      target: :WATCH,
    )
  end

  def dashboard_empty_feed_follow_data_attributes(analytics_dimensions)
    dashboard_hydro_click_tracking_attributes(
      event_context: Dashboard::EventContext::EMPTY_FEED,
      target: :FOLLOW,
    )
  end

  def dashboard_empty_feed_star_data_attributes(analytics_dimensions)
    dashboard_hydro_click_tracking_attributes(
      event_context: Dashboard::EventContext::EMPTY_FEED,
      target: :STAR_REPOSITORIES,
    )
  end

  def dashboard_empty_feed_explore_data_attributes(analytics_dimensions)
    dashboard_hydro_click_tracking_attributes(
      event_context: Dashboard::EventContext::EMPTY_FEED,
      target: :EXPLORE,
    )
  end

  def dashboard_repositories_org_profile_data_attributes
    dashboard_hydro_click_tracking_attributes(
      event_context: Dashboard::EventContext::Sidebar::REPOSITORIES,
      target: :ORG_PROFILE,
    )
  end

  def organization_create_repo_data_attributes
    dashboard_hydro_click_tracking_attributes(
      event_context: Dashboard::EventContext::ORGANIZATIONS,
      target: :CREATE_REPO,
    )
  end

  def organization_view_team_data_attributes
    dashboard_hydro_click_tracking_attributes(
      event_context: Dashboard::EventContext::ORGANIZATIONS,
      target: :VIEW_TEAM,
    )
  end

  def organization_see_owners_data_attributes
    dashboard_hydro_click_tracking_attributes(
      event_context: Dashboard::EventContext::ORGANIZATIONS,
      target: :SEE_OWNERS,
    )
  end

  def organization_browse_repositories_data_attributes
    dashboard_hydro_click_tracking_attributes(
      event_context: Dashboard::EventContext::ORGANIZATIONS,
      target: :REPOSITORY,
    )
  end

  def organization_edit_settings_data_attributes
    dashboard_hydro_click_tracking_attributes(
      event_context: Dashboard::EventContext::ORGANIZATIONS,
      target: :EDIT_SETTINGS,
    )
  end

  def organization_return_personal_dash_data_attributes
    dashboard_hydro_click_tracking_attributes(
      event_context: Dashboard::EventContext::ORGANIZATIONS,
      target: :RETURN_PERSONAL_DASH,
    )
  end

  def organization_learn_more_data_attributes
    dashboard_hydro_click_tracking_attributes(
      event_context: Dashboard::EventContext::ORGANIZATIONS,
      target: :LEARN_MORE,
    )
  end

  def discover_repositories_explore_attributes
    context = current_context.class.to_s.downcase
    hydro_click_tracking_attributes(
      "dashboard.click",
      event_context: Dashboard::EventContext::DISCOVER_REPOSITORIES,
      target: :EXPLORE,
      dashboard_context: context,
      dashboard_version: DASHBOARD_VERSION,
      user_id: current_user&.id,
    )
  end

  def discover_repositories_attributes(repo_id, target)
    context = current_context.class.to_s.downcase
    hydro_click_tracking_attributes(
      "dashboard.click",
      event_context: Dashboard::EventContext::DISCOVER_REPOSITORIES,
      target: target.sub(" ", "_").upcase.to_sym,
      record_id: repo_id,
      dashboard_context: context,
      dashboard_version: DASHBOARD_VERSION,
      user_id: current_user&.id,
    )
  end

  def sidebar_repository_attributes(repo: nil, button: false, event_context: nil, metadata: nil)
    context = current_context.class.to_s.downcase
    if button
      hydro_click_tracking_attributes("dashboard.click",
        event_context: event_context || Dashboard::EventContext::Sidebar::REPOSITORIES,
        target: :NEW_REPOSITORY_BUTTON,
        dashboard_context: context,
        dashboard_version: DASHBOARD_VERSION,
        user_id: current_user&.id,
        metadata: metadata,
      )
    elsif repo
      visibility = repo[:private] ? "private" : "public"
      repo_id = Platform::Helpers::NodeIdentification.from_global_id(repo[:id]).last&.to_i
      hydro_click_tracking_attributes("dashboard.click",
        event_context: event_context || Dashboard::EventContext::Sidebar::REPOSITORIES,
        target: :REPOSITORY,
        record_id: repo_id,
        dashboard_context: context,
        dashboard_version: DASHBOARD_VERSION,
        user_id: current_user&.id,
        metadata: metadata,
      )
    else
      hydro_click_tracking_attributes("dashboard.click",
        event_context: Dashboard::EventContext::Sidebar::REPOSITORIES,
        target: :SEE_MORE,
        dashboard_context: context,
        dashboard_version: DASHBOARD_VERSION,
        user_id: current_user&.id,
        metadata: metadata,
      )
    end
  end

  def sidebar_team_attributes(team: nil)
    context = current_context.class.to_s.downcase
    if team
      hydro_click_tracking_attributes("dashboard.click",
        event_context: Dashboard::EventContext::Sidebar::TEAMS,
        target: :TEAM,
        record_id: team.id,
        dashboard_context: context,
        dashboard_version: DASHBOARD_VERSION,
        user_id: current_user&.id,
      )
    else
      hydro_click_tracking_attributes("dashboard.click",
        event_context: Dashboard::EventContext::Sidebar::TEAMS,
        target: :SEE_MORE,
        dashboard_context: context,
        dashboard_version: DASHBOARD_VERSION,
        user_id: current_user&.id,
      )
    end
  end

  def sidebar_recent_interaction_attributes(type: nil, reason: nil, id: nil)
    context = current_context.class.to_s.downcase
    if type && reason && id
      record_id = Platform::Helpers::NodeIdentification.from_global_id(id).last&.to_i
      hydro_click_tracking_attributes("dashboard.click",
        event_context: Dashboard::EventContext::Sidebar::RECENT_ACTIVITY,
        target: type.sub(" ", "_").upcase.to_sym,
        record_id: record_id,
        dashboard_context: context,
        dashboard_version: DASHBOARD_VERSION,
        user_id: current_user&.id,
      )
    else
      hydro_click_tracking_attributes("dashboard.click",
        event_context: Dashboard::EventContext::Sidebar::RECENT_ACTIVITY,
        target: :SEE_MORE,
        dashboard_context: context,
        dashboard_version: DASHBOARD_VERSION,
        user_id: current_user&.id,
      )
    end
  end
end
