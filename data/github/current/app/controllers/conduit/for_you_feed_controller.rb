# typed: true
# frozen_string_literal: true

module Conduit
  class ForYouFeedController < ApplicationController
    include OrganizationsHelper
    include GitHub::Memoizer

    before_action :login_required, :require_xhr
    before_action :require_conduit_feed_enabled?
    before_action :ensure_feed
    around_action :record_show_stats

    depends_on_clusters ApplicationRecord::Mysql1,
      ApplicationRecord::Ballast,
      ApplicationRecord::Collab,
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
      only: [:show], optional: true

    def show
      GitHub.dogstats.increment("conduit.get_feed", tags: ["success:true"])

      GlobalInstrumenter.instrument("feeds.feed_retrieved", {
        feed_cards:   feed.items,
        actor:        current_user,
        retrieved_at: Time.now.utc,
        original_request_id: this_request_id,
        metadata:     {
          filter_groups: feed_filter&.enabled_group_keys.to_s,
        },
      })

      respond_to do |format|
        format.html do
          render partial: "conduit/feed", locals: {
            feed: feed,
            feeds_dev_analytics: feeds_dev_analytics,
            filter_values: feed_filter&.values,
            show_star_repo_buttons: show_star_repo_buttons?,
            show_stats: show_stats,
            next_page_path: conduit_for_you_feed_path(page: feed.next_page, o_request_id: feed.request_id),
            exp_context: exp_context,
            viewer: current_user,
            requested_from_filter_event: params[:requested_from_filter_event]
          }
        end
      end
    end

    private

    attr_reader :feed

    def require_xhr
      render_404 unless request.xhr? || current_user.employee? || turbo_frame_request?
    end

    memoize def feed_filter
      if is_dashboard_feed?
        values = Conduit::FeedFilter.include_all_filter
      else
        filter = ForYouFeedFilterSettings.where(user_id: current_user.id).first
        values = filter&.values
      end
      Conduit::FeedFilter.new(values, viewer: current_user)
    end

    def ensure_feed
      @feed = T.let(nil, T.untyped)
      GitHub.dogstats.distribution_time("conduit.for_you_feed.response_time", tags: for_you_feed_tags("success:true")) do
        @feed ||= Conduit::Web.for_you_feed(
          user: current_user,
          page: current_page,
          filter: feed_filter,
          request_id: this_request_id,
          disable_conduit_cache: disable_conduit_cache?,
          exp_context: exp_context,
          cap_filter: cap_filter,
        )
        GitHub.dogstats.increment("conduit.for_you_feed.requests.count", tags: for_you_feed_tags("success:true"))
      end

    rescue Conduit::Client::Error, Faraday::ConnectionFailed => e
      GitHub.dogstats.increment("conduit.for_you_feed.requests.count", tags: for_you_feed_tags("success:false"))
      report_error(e)
      render partial: "conduit/feed", locals: {
        error: e.message,
      }
    end

    def for_you_feed_tags(success_tag)
      [
        "source:for_you_feed",
        success_tag,
        "xhr:#{request.xhr?}",
        "cache_disabled:#{disable_conduit_cache?}"
      ]
    end

    memoize def exp_context
      ::Conduit::ExpContext.new(current_user)
    end

    def feeds_dev_analytics
      user_feature_enabled?(:feeds_dev_analytics)
    end

    def show_star_repo_buttons?
      !FeatureFlag.vexi.enabled?(:disable_starred_repos_button_on_dashboard_feed, current_user, default: false)
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

    def resource_for_conditional_access
      return :no_resource_for_conditional_access unless logged_in? # rubocop:disable GitHub/SpecifyResourceForConditionalAccess
      current_user
    end

    def target_for_conditional_access
      return :no_target_for_conditional_access unless logged_in? # rubocop:disable GitHub/SpecifyTargetForConditionalAccess
      current_user
    end

    def require_conduit_feed_enabled?
      render_404 unless GitHub.conduit_enabled?(user: current_user)
    end

    def disable_conduit_cache?
      user_feature_enabled?(:feeds_conduit_cache_opt_out) || is_dashboard_feed? || params[:opt_out_conduit_cache] == "true"
    end

    def is_dashboard_feed?
      params[:source] == "dashboard_feed"
    end
  end
end
