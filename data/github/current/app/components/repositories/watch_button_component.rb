# typed: true
# frozen_string_literal: true

require "notifyd-client"

module Repositories
  class WatchButtonComponent < ApplicationComponent
    include AnalyticsHelper
    include HydroHelper
    include RepositoryAnalyticsHelper
    include UsersHelper
    include EnterpriseManagedUsersHelper

    def initialize(repository:, aria_id_prefix:, status: nil)
      @aria_id_prefix = aria_id_prefix
      @repository = repository
      @status = status
    end

    private

    def subscribable_thread_types
      thread_type_info = []

      thread_type_info << { name: "Issue", enabled: @repository.has_issues, subscribed: thread_type_subscribed?("Issue") }
      thread_type_info << { name: "PullRequest", enabled: true, subscribed: thread_type_subscribed?("PullRequest") }
      thread_type_info << { name: "Release", enabled: true, subscribed: thread_type_subscribed?("Release") }

      if @repository.eligible_for_discussions?
        thread_type_info << { name: "Discussion", enabled: @repository.discussions_active?, subscribed: thread_type_subscribed?("Discussion") }
      end

      thread_type_info << { name: "SecurityAlert", enabled: true, subscribed: thread_type_subscribed?("SecurityAlert") }

      thread_type_info
    end

    def thread_type_subscribed?(thread_type)
      return nil unless @status
      !@status.ignored? && @status.thread_types.include?(thread_type)
    end

    def subscribed_labels
      if show_label_subscriptions?
        return @repository.subscribed_labels(current_user)
      end

      []
    end

    def repository_labels
      if show_label_subscriptions?
        subscribed_labels = @repository.subscribed_labels(current_user)
        return @repository.sorted_labels(cache_label_html: true).map do |label|
          {
            id: label.id,
            name: label.name,
            html: label.name_html,
            color: label.color,
            description: label.description,
            subscribed: subscribed_labels.include?(label)
          }
        end
      end

      []
    end

    def show_label_subscriptions?
      Notifyd::Flags.new(current_user).label_subscriptions?(@repository)
    end

    def show_mobile_promo?
      !T.must(current_user).uses_mobile_app?
    end

    def mobile_promo_html
      safe_join([
        "Get push notifications on ",
        safe_link_to("iOS", ios_mobile_app_store_url(campaign: "watch-dropdown"), target: "_blank"),
        " or ",
        safe_link_to("Android", android_mobile_app_store_url(campaign: "watch-dropdown"), target: "_blank"),
        "."
      ])
    end

    def render?
      @repository.present?
    end

    def can_watch?
      return false unless logged_in?
      !emu_contribution_blocked?(@repository)
    end

    def subscription_type
      return nil if !@status

      # @status may be a Newsies::Responses::Subscription which wraps a subscription but may
      # not be a success?
      return nil if @status.respond_to?(:success?) && !@status.success?

      if @status.subscribed?
        :watching
      elsif @status.thread_types.any?
        :custom
      elsif @status.participation_only?
        :none
      elsif @status.ignored?
        :ignoring
      end
    end
  end
end
