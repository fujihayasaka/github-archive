# typed: true
# frozen_string_literal: true

module Teams
  class NotificationsComponent < ApplicationComponent
    include AnalyticsHelper
    include HydroHelper
    include TeamsHelper

    renders_one :fallback_error
    renders_one :spinner

    def initialize(team:, status:, beta: false, deferred: false, button_size: :md)
      @team = team
      @status = status
      @organization = @team&.organization
      @beta = beta
      @deferred = deferred
      @button_size = button_size
    end

    private

    attr_reader :deferred, :beta, :button_size
    alias_method :deferred?, :deferred

    def render?
      @team.present?
    end

    def enhanced_team_posts_enabled?
      GitHub.flipper[:enhanced_team_posts].enabled?(@organization)
    end

    def ignorable_team_notifications?
      GitHub.flipper[:ignorable_team_notifications].enabled?(current_user) && GitHub.flipper[:ignorable_team_notifications].enabled?(@organization)
    end

    def summary_attribute_for(status)
      if subscription_type == status
        test_selector("current-subscription-status")
      else
        "hidden"
      end
    end

    def watch_button_size_class
      return "btn-md" unless @button_size

      "btn-#{@button_size}"
    end

    def participation_secondary_text
      team_posts_text = "Only receive notifications for team posts when participating or @mentioned."
      team_discussions_text = "Only receive notifications for team discussions when participating or @mentioned."

      enhanced_team_posts_enabled? ? team_posts_text : team_discussions_text
    end

    def watching_secondary_text
      team_posts_text = "Receive notifications for all team posts."
      team_discussions_text = "Receive notifications for all team discussions."

      enhanced_team_posts_enabled? ? team_posts_text : team_discussions_text
    end

    def ignoring_secondary_text
      team_ignorable_text = "Never receive notifications from this team."
      team_posts_text = "Never receive notifications for team posts."
      team_discussions_text = "Never receive notifications for team discussions."

      if enhanced_team_posts_enabled?
        ignorable_team_notifications? ? team_ignorable_text : team_posts_text
      else
        team_discussions_text
      end
    end

    def subscription_type
      return nil if !@status

      # @status may be a Newsies::Responses::Subscription which wraps a subscription but may
      # not be a success?
      return nil if @status.respond_to?(:success?) && !@status.success?

      if @status.subscribed?
        :watching
      elsif @status.participation_only?
        :none
      elsif @status.ignored?
        :ignoring
      end
    end
  end
end
