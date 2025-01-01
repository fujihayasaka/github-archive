# typed: true
# frozen_string_literal: true

module Conduit
  class FilterController < ApplicationController
    extend T::Sig

    before_action :login_required, :require_xhr
    before_action :validate_filter_params, only: [:update]
    before_action :require_conduit_feed_enabled?

    depends_on_clusters ApplicationRecord::Mysql1,
      ApplicationRecord::Collab,
      ApplicationRecord::Ballast,
      ApplicationRecord::Repositories,
      ApplicationRecord::Mysql5,
      ApplicationRecord::IamAbilities,
      ApplicationRecord::Mysql2,
      ApplicationRecord::NotificationsEntries,
      ApplicationRecord::IssuesPullRequests,
      only: [:show]

    depends_on_clusters ApplicationRecord::Copilot,
      only: [:show], optional: true

    def show
      if user_feature_enabled?(:feeds_v2)
        if is_org_feed?
          respond_to do |format|
            format.html do
              render ::Feed::ItemOrgFilterNextComponent.new(
                T.let(params[:org], String),
                feed_filter: feed_filter,
                user: @current_user,
              ), layout: false
            end
          end
        else
          respond_to do |format|
            format.html do
              render ::Feed::ItemFilterNextComponent.new(
                feed_filter: feed_filter,
                user: @current_user,
                is_topic: is_topic_feed?,
              ), layout: false
            end
          end
        end
      else
        respond_to do |format|
          format.html do
            render ::Feed::ItemFilterComponent.new(
              feed_filter: feed_filter,
              is_topic: is_topic_feed?,
            ), layout: false
          end
        end
      end
    end

    def update
      update_feed_filter!

      respond_to do |format|
        format.html do
          if is_topic_feed?
            render partial: "dashboard/include_for_you_feed", locals: {
              url: conduit_topic_feeds_path(topic: params[:topic]),
            }, layout: false
          elsif is_org_feed?
            render partial: "dashboard/include_org_feed", locals: {
              url: conduit_org_feeds_path(org: params[:org]),
            }, layout: false
          else
            render partial: "dashboard/include_for_you_feed", locals: {
              url: conduit_for_you_feed_path(requested_from_filter_event: true),
            }, layout: false
          end
        end
      end
    end

    private

    memoize def exp_context
      ::Conduit::ExpContext.new(current_user)
    end

    memoize def update_filter_value
      JSON.parse(request.body.read)
    end

    memoize def feed_filter
      if is_topic_feed?
        topic_feed_filter
      elsif is_org_feed?
        org_feed_filter
      else
        for_you_feed_filter
      end
    end

    memoize def topic_feed_filter
      filter = FeedFilterSettings.where(user_id: current_user.id, is_topic: true).first
      Conduit::FeedFilter.new(filter&.values, viewer: current_user)
    end

    memoize def for_you_feed_filter
      filter = ForYouFeedFilterSettings.where(user_id: current_user.id).first
      Conduit::FeedFilter.new(filter&.values, viewer: current_user)
    end

    memoize def org_feed_filter
      filter = OrganizationFeedFilterSettings.where(user_id: current_user.id).first
      Conduit::OrgFeedFilter.new(filter&.values, viewer: current_user)
    end

    def update_feed_filter!
      return unless valid_filter?

      if is_topic_feed?
        current_user.set_feed_filter!(true, update_filter_value)
      elsif is_org_feed?
        current_user.set_org_feed_filter!(true, update_filter_value)
      else
        current_user.set_for_you_feed_filter!(update_filter_value)
      end
      Conduit::KVBackedCache.invalidate_for(current_user)
    end

    def valid_filter?
      return false if update_filter_value.blank?

      update_filter_value.keys.all? { |key| Conduit::FeedFilter.is_valid_group?(key) }
    end

    def validate_filter_params
      return if valid_filter?
      head 404
    end

    def resource_for_conditional_access
      return :no_resource_for_conditional_access unless logged_in? # rubocop:disable GitHub/SpecifyResourceForConditionalAccess
      current_user
    end

    def target_for_conditional_access
      return :no_target_for_conditional_access unless logged_in? # rubocop:disable GitHub/SpecifyTargetForConditionalAccess
      current_user
    end

    def require_xhr
      render_404 unless request.xhr?
    end

    def require_conduit_feed_enabled?
      render_404 unless GitHub.conduit_feed_enabled?
    end

    def is_topic_feed?
      params["is_topic"] == "true"
    end

    def is_org_feed?
      params["org"].present?
    end
  end
end
