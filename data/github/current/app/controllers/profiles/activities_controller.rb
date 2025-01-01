# typed: true
# frozen_string_literal: true

module Profiles
  class ActivitiesController < ::ApplicationController
    depends_on_clusters ApplicationRecord::Mysql1,
      ApplicationRecord::Mysql5,
      ApplicationRecord::Collab,
      ApplicationRecord::IamAbilities,
      ApplicationRecord::Mysql2,
      ApplicationRecord::IssuesPullRequests,
      ApplicationRecord::NotificationsEntries,
      ApplicationRecord::Configurations,
      ApplicationRecord::Repositories,
      only: [:index]

    depends_on_clusters ApplicationRecord::Copilot,
      only: [:index],
      optional: true

    include ProfilesHelper
    include GitHub::Memoizer

    before_action :require_feeds_enabled
    before_action :require_user
    before_action :require_feature
    before_action :require_public_profile
    before_action :require_public_profile_feed
    around_action :record_show_stats, only: :index

    javascript_bundle :dashboard, :profile
    stylesheet_bundle :dashboard, :profile, :discussions

    def index
      instrument_hydro

      if request.xhr?
        render_feed
      else
        render_activities_tab
      end
    end

    private

    def render_feed
      render partial: "conduit/feed", locals: {

        show_star_repo_buttons: true,
        feed: feed,
        show_stats: show_stats,
        viewer: current_user,
        next_page_path: user_activities_path(
          tab: "activity",
          page: feed.next_page,
          o_request_id: this_request_id,
        ) }
    end

    def render_activities_tab
      render "users/tabs/activities/index", locals: {
        user: this_user,
        richweb_attributes: Profiles::User::RichwebAttributes.build(layout_data, nil, []),
        layout_data: layout_data,
        profile_feed_visibility_setting: profile_feed_visibility_setting,
        feed: feed,
        show_stats: show_stats,
        next_page_path: user_activities_path(
          tab: "activity",
          page: feed.next_page,
          o_request_id: this_request_id,
        )
      }
    end

    def layout_data
      Profiles::User::LayoutData.preload(
        profile_user: this_user,
        viewer: current_user,
        active_tab: :activity,
      )
    end

    def feed
      @feed ||= Conduit::Web.profile_feed(
        user: this_user,
        viewer: current_user,
        page: current_page,
        request_id: this_request_id
      )
    rescue Conduit::Client::Error, Faraday::ConnectionFailed => e
      report_error(e)
      render partial: "conduit/feed", locals: {
        error: e.message,
      }, layout: false
    end

    def instrument_hydro
      GlobalInstrumenter.instrument("user_profile.page_view",
        has_organization_memberships: this_user.organizations.any?,
        profile_user: this_user,
        profile_viewer: current_user,
        scoped_org_id: nil,
        selected_tab: :ACTIVITY,
      )
    end

    memoize def this_user
      ::User.find_by_login(params[:user_id]) if params[:user_id] && GitHub::UTF8.valid_unicode3?(params[:user_id])
    end

    def target_for_conditional_access
      return :no_target_for_conditional_access unless this_user.present? # rubocop:disable GitHub/SpecifyTargetForConditionalAccess
      this_user
    end

    def require_user
      render_404 unless this_user
    end

    def require_feature
      redirect_to user_path(this_user) unless user_or_global_feature_enabled?(:feed_posts)
    end

    memoize def this_request_id
      params[:o_request_id].presence || request_id
    end

    memoize def show_stats
      Conduit::ShowStats.new(
        feed: feed,
        viewer: current_user,
      )
    end

    memoize def profile_feed_visibility_setting
      this_user.settings.get(:user_profile_feed_visible)
    end

    def record_show_stats
      show_stats.instrument_controller_action do
        yield
        response
      end
    end

    def report_error(e)
      Failbot.report(e)
      GitHub.dogstats.increment("conduit.get_user_feed", tags: ["success:false"])
    end

    def require_public_profile
      if this_user.private_profile_for?(current_user)
        redirect_to user_path(this_user)
      end
    end

    def require_public_profile_feed
      return if this_user == current_user || profile_feed_visibility_setting
      redirect_to user_path(this_user)
    end

    def require_feeds_enabled
      unless GitHub.conduit_feed_enabled?
        redirect_to user_path(this_user)
      end
    end
  end
end
