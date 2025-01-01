# typed: true
# frozen_string_literal: true

module Conduit
  class UserListFeedsController < ApplicationController
    include ProfilesHelper # for `ensure_profile_visible`
    include UserListsControllerMethods
    include GitHub::Memoizer

    before_action :login_required, :require_xhr
    before_action :require_feature_enabled
    before_action :require_this_user
    before_action :ensure_profile_visible
    before_action :require_user_list
    before_action :require_conduit_feed_enabled?
    before_action :ensure_feed
    around_action :record_show_stats

    depends_on_clusters ApplicationRecord::Mysql1,
      ApplicationRecord::Collab,
      ApplicationRecord::Ballast,
      ApplicationRecord::Repositories,
      ApplicationRecord::Mysql5,
      ApplicationRecord::IamAbilities,
      ApplicationRecord::Mysql2,
      ApplicationRecord::NotificationsEntries,
      ApplicationRecord::IssuesPullRequests,
      ApplicationRecord::RepositoriesPushes,
      ApplicationRecord::Configurations,
      ApplicationRecord::Spokes

    depends_on_clusters ApplicationRecord::Copilot,
      only: [:show],
      optional: true

    def show
      GitHub.dogstats.increment("conduit.get_user_list_feed", tags: ["success:true"])
      # GlobalInstrumenter.instrument("feeds.feed_retrieved", {
      #   feed_cards:   feed.items,
      #   actor:        current_user,
      #   retrieved_at: Time.now.utc,
      #   original_request_id: this_request_id,
      #   metadata:     {
      #     filter_groups:  feed_filter&.enabled_group_keys.to_s,
      #   },
      # })

      respond_to do |format|
        format.html do
          render partial: "conduit/feed", locals: {
            feed: feed,

            feeds_dev_analytics: feeds_dev_analytics,
            show_star_repo_buttons: show_star_repo_buttons?,
            show_stats: show_stats,
            viewer: current_user,
            next_page_path: user_list_activity_path(
              user: this_user,
              page: feed.next_page,
              o_request_id: feed.request_id,
              user_list_slug: params[:user_list_slug],
            ),
          }
        end
      end
    end

    private

    attr_reader :feed

    def require_xhr
      render_404 unless request.xhr? || current_user.employee? || turbo_frame_request?
    end

    def ensure_feed
      @feed ||= Conduit::Web.topic_feed(
        viewer: current_user,
        list: list,
        page: current_page,
        filter: topic_feed_filter,
        request_id: this_request_id,
        cap_filter: cap_filter,
      )
    rescue Conduit::Client::Error, Faraday::ConnectionFailed => e
      report_error(e)
      render partial: "conduit/feed", locals: {
        error: e.message,
      }
    end

    def list
      entries = user_list
        .repositories
        .map { |repo| "#{repo.id}|repository" }

      return "" if entries.empty?

      entries
    end

    def feeds_dev_analytics
      user_feature_enabled?(:feeds_dev_analytics)
    end

    def show_star_repo_buttons?
      !user_feature_enabled?(:disable_starred_repos_button_on_dashboard_feed)
    end

    def report_error(e)
      Failbot.report(e)
      GitHub.dogstats.increment("conduit.get_feed", tags: ["success:false"])
    end

    memoize def show_stats
      if action_name == "show"
        ::Conduit::ShowStats.new(feed: feed, viewer: current_user)
      end
    end

    def record_show_stats
      show_stats.instrument_controller_action do
        yield
        response
      end
    end

    memoize def this_request_id
      params[:o_request_id].presence || request_id
    end

    memoize def topic_feed_filter
      filter = FeedFilterSettings.where(user_id: current_user.id, is_topic: true).first
      Conduit::FeedFilter.new(filter&.values, viewer: current_user)
    end

    memoize def feed_filter
      filter = ForYouFeedFilterSettings.where(user_id: current_user.id).first
      Conduit::FeedFilter.new(filter&.values, viewer: current_user)
    end

    memoize def user_list
      if this_user && GitHub::UTF8.valid_unicode3?(params[:user_list_slug])
        this_user.lists.find_by(slug: params[:user_list_slug])
      end
    end

    def resource_for_conditional_access
      return :no_resource_for_conditional_access unless logged_in? # rubocop:disable GitHub/SpecifyResourceForConditionalAccess
      current_user
    end

    def target_for_conditional_access
      return :no_target_for_conditional_access unless logged_in? # rubocop:disable GitHub/SpecifyTargetForConditionalAccess
      current_user
    end

    def require_conduit_feed_enabled?
      render_404 unless GitHub.conduit_feed_enabled?
    end

    def require_user_list
      render_404 unless user_list.present?
    end

    def require_feature_enabled
      render_404 unless user_feature_enabled?(:user_list_feed)
    end
  end
end
