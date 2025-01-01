# typed: true
# frozen_string_literal: true
require "notifyd-client"

module Repositories
  class NotificationsComponent < ApplicationComponent
    include AnalyticsHelper
    include HydroHelper
    include RepositoryAnalyticsHelper
    include UsersHelper
    include EnterpriseManagedUsersHelper
    include ReactHelper

    renders_one :fallback_error
    renders_one :spinner

    # Required to ensure that each rendered watch button on the page
    # has unique aria ids. This value should be unique on the page.
    attr_reader :aria_id_prefix, :deferred_content, :show_count, :button_block
    alias_method :deferred?, :deferred_content

    SHOW_COUNT_DEFAULT = false
    SHOW_COUNT_OPTIONS = [SHOW_COUNT_DEFAULT, true]

    BUTTON_BLOCK_DEFAULT = false
    BUTTON_BLOCK_OPTIONS = [BUTTON_BLOCK_DEFAULT, true]

    def initialize(
      repository:,
      aria_id_prefix:,
      status: nil,
      button_block: BUTTON_BLOCK_DEFAULT,
      show_count: SHOW_COUNT_DEFAULT,
      unwatch_hydro_tracking_attributes: nil,
      deferred_content: false,
      auto_focus: false
    )
      @repository = repository
      @aria_id_prefix = aria_id_prefix
      @status = status

      @unwatch_hydro_tracking_attributes = unwatch_hydro_tracking_attributes

      @button_block = fetch_or_fallback(BUTTON_BLOCK_OPTIONS, button_block, BUTTON_BLOCK_DEFAULT)
      @show_count = fetch_or_fallback(SHOW_COUNT_OPTIONS, show_count, SHOW_COUNT_DEFAULT)
      @deferred_content = deferred_content
      @auto_focus = auto_focus
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

    def watcher_count
      @repository.watchers_count
    end

    def show_button_counter?
      @show_count
    end

    def notifications_button_component(**extra)
      args = { variant: :small, block: @button_block }
      Primer::ButtonComponent.new(**args.merge(extra))
    end

    def thread_type_subscribed?(thread_type)
      !@status.ignored? && @status.thread_types.include?(thread_type)
    end

    def subscribed_labels
      if show_label_subscriptions?
        return @repository.subscribed_labels(current_user)
      end

      []
    end

    def show_label_subscriptions?
      Notifyd::Flags.new(current_user).label_subscriptions?(@repository)
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

    def auto_focus_watch?
      @auto_focus
    end

    class CounterComponent < ApplicationComponent
      def initialize(repository:)
        @repository = repository
      end

      def call
        render(Primer::Beta::Counter.new(
          id: "repo-notifications-counter",
          count: @repository.watchers_count,
          round: true,
          limit: nil,
          data: {
            target: "notifications-list-subscription-form.socialCount",
            pjax_replace: true,
            turbo_replace: true,
          },
        ))
      end
    end
  end
end
