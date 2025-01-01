# typed: true
# frozen_string_literal: true

module Conduit
  class OrgFeedsController < ApplicationController
    include OrganizationsHelper
    include GitHub::Memoizer

    before_action :login_required, :require_xhr
    before_action :require_conduit_org_feeds_enabled?
    before_action :current_organization, presence: true
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
      only: [:show], optional: true

    def show
      # GitHub.dogstats.increment("conduit.get_org_feed", tags: ["success:true"])

      # GlobalInstrumenter.instrument("feeds.org_feed_retrieved", {
      #   feed_cards:   feed.items,
      #   actor:        current_user,
      #   retrieved_at: Time.now.utc,
      #   original_request_id: this_request_id,
      # })

      respond_to do |format|
        format.html do
          render partial: "conduit/org_feed", locals: {
            feed: feed,
            feeds_dev_analytics: feeds_dev_analytics,
            show_stats: show_stats,
            next_page_path: conduit_org_feeds_path(org: current_organization, page: feed.next_page, o_request_id: feed.request_id),
            viewer: current_user,
          }
        end
      end

    end

    private

    attr_reader :feed

    def require_xhr
      render_404 unless request.xhr? || current_user.employee? || turbo_frame_request?
    end

    memoize def current_organization
      @current_organization ||= Organization.find_by_login(params[:org])
    end

    def ensure_feed
      @feed ||= Conduit::Web.org_feed(
        viewer: current_user,
        org: current_organization,
        page: current_page,
        filter: feed_filter,
        request_id: this_request_id,
        cap_filter: cap_filter,
      )
    rescue Conduit::Client::Error, Faraday::ConnectionFailed => e
      report_error(e)
      render partial: "conduit/org_feed", locals: {
        error: e.message,
      }
    end

    def feeds_dev_analytics
      user_feature_enabled?(:feeds_dev_analytics)
    end

    def report_error(e)
      Failbot.report(e)
      GitHub.dogstats.increment("conduit.get_org_feed", tags: ["success:false"])
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

    memoize def feed_filter
      filter = OrganizationFeedFilterSettings.where(user_id: current_user.id).first
      Conduit::OrgFeedFilter.new(filter&.values, viewer: current_user)
    end

    def resource_for_conditional_access
      return :no_resource_for_conditional_access unless logged_in? # rubocop:disable GitHub/SpecifyResourceForConditionalAccess
      current_user
    end

    def target_for_conditional_access
      return :no_target_for_conditional_access unless logged_in? # rubocop:disable GitHub/SpecifyTargetForConditionalAccess
      current_user
    end

    def require_conduit_org_feeds_enabled?
      render_404 unless user_or_global_feature_enabled?(:conduit_org_feeds)
    end
  end
end
