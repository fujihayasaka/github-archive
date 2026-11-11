# typed: true
# frozen_string_literal: true

module DependabotAlerts
  class TimelineComponent < ApplicationComponent
    include ViewComponent::InlineTemplate

    erb_template <<~'ERB'
      <% timeline_items.each do |timeline_item| %>
        <%= render timeline_item %>
      <% end %>
    ERB

    attr_reader :alert

    MAX_EVENTS_ON_FIRST_RENDER = 20

    def initialize(alert:, before: nil, after: nil, current_user: nil)
      @alert = alert
      @before = before
      @after = after
      @current_user = current_user
    end

    memoize def events
      regular_events = if show_all_events?
        alert.events.order(:created_at).preload(:actor, :assignee).to_a
      else
        first_events + last_events
      end

      dismissal_events = dismissal_timeline_events

      # Combine and sort by created_at timestamp
      all_events = regular_events + dismissal_events
      all_events.sort_by { |event| event_timestamp(event) }
    end

    memoize def hidden_events
      return [] unless @before && @after

      alert.events.between(after_id: @after, before_id: @before).order(:id).preload(:actor, :assignee).to_a
    end

    def show_load_all?(index:)
      index == 10 && !show_all_events?
    end

    def load_all_path
      after, before = first_events.last.id, last_events.first.id
      "#{alert.permalink(include_host: false)}/events?after=#{after}&before=#{before}"
    end

    private

    memoize def event_count
      regular_count = alert.events.count
      dismissal_count = dismissal_timeline_events.count
      regular_count + dismissal_count
    end

    memoize def dismissal_timeline_events
      return [] unless alert.repository.owner.is_a?(Organization)
      return [] unless @current_user.present?

      delegated_closures = Dependabot::SecurityProduct::DelegatedClosures.new(alert.repository)
      return [] unless delegated_closures.enabled?

      Dependabot::SecurityProduct::DelegatedClosures.get_timeline_events(
        repository: alert.repository,
        alert_number: alert.number,
        viewer: @current_user
      )
    end

    def event_timestamp(event)
      return event.created_at if event.respond_to?(:created_at)
      return Time.at(event.timestamp.seconds, event.timestamp.nanos, :nsec) if event.respond_to?(:timestamp) && event.timestamp

      Time.current
    end

    def show_all_events?
      event_count <= MAX_EVENTS_ON_FIRST_RENDER
    end

    memoize def first_events
      alert.events.order(:id).limit(10).preload(:actor, :assignee).to_a
    end

    memoize def last_events
      @last_events ||= alert.events.order(id: :desc).limit(10).preload(:actor, :assignee).to_a.reverse
    end

    def hidden_items_count
      return 0 if show_all_events?
      event_count - MAX_EVENTS_ON_FIRST_RENDER
    end

    def determine_timeline_event_component(event:, last_event:)
      case event.event.to_sym
      when :dismissed
        DependabotAlerts::TimelineItems::DismissedComponent.new(event: event, actor: event.actor, last_event: last_event)
      when :fixed
        DependabotAlerts::TimelineItems::FixedComponent.new(event: event, last_event: last_event)
      when :reopened
        DependabotAlerts::TimelineItems::ReopenedComponent.new(event: event, actor: event.actor, last_event: last_event)
      when :reintroduced
        DependabotAlerts::TimelineItems::ReintroducedComponent.new(event: event, last_event: last_event)
      when :auto_dismissed
        DependabotAlerts::TimelineItems::AutoDismissedComponent.new(alert: alert, event: event, last_event: last_event)
      when :auto_reopened
        DependabotAlerts::TimelineItems::AutoReopenedComponent.new(alert: alert, event: event, last_event: last_event)
      when :assigned
        DependabotAlerts::TimelineItems::AssignmentComponent.new(event: event, actor: event.actor, assignee: event.assignee, action: :assigned, last_event: last_event)
      when :unassigned
        DependabotAlerts::TimelineItems::AssignmentComponent.new(event: event, actor: event.actor, assignee: event.assignee, action: :unassigned, last_event: last_event)
      when :copilot_work_started
        DependabotAlerts::TimelineItems::CopilotWorkStartedComponent.new(event: event, actor: event.actor, alert: alert, last_event: last_event)
      when :copilot_work_finished
        DependabotAlerts::TimelineItems::CopilotWorkFinishedComponent.new(event: event, actor: event.actor, alert: alert, last_event: last_event)
      end
    end

    def determine_dismissal_timeline_event_component(timeline_event:, last_event:)
      # Find the user for the timeline event
      user = timeline_event.user_id ? User.find_by(id: timeline_event.user_id) : nil

      case timeline_event.type
      when :TIMELINE_EVENT_TYPE_ALERT_DISMISSAL_REQUESTED
        DependabotAlerts::TimelineItems::DismissalRequestedComponent.new(
          timeline_event: timeline_event,
          actor: user,
          last_event: last_event,
          dismissal_request_review_path: review_dismissal_request_path,
          alert: alert
        )
      when :TIMELINE_EVENT_TYPE_ALERT_DISMISSAL_REVIEWED
        DependabotAlerts::TimelineItems::DismissalReviewedComponent.new(
          timeline_event: timeline_event,
          actor: user,
          last_event: last_event
        )
      when :TIMELINE_EVENT_TYPE_ALERT_DISMISSAL_CANCELLED
        DependabotAlerts::TimelineItems::DismissalCancelledComponent.new(
          timeline_event: timeline_event,
          actor: user,
          last_event: last_event
        )
      end
    end

    def review_dismissal_request_path
      # This should match the route we defined in the controller
      urls.repository_dependabot_dismissal_request_review_path(
        alert.repository.owner,
        alert.repository
      )
    end

    memoize def urls
      ViewModel::URLs.new
    end

    memoize def timeline_items
      @timeline_items = []
      # if before and after params are present,
      # we need to build the events for the middle of the timeline
      # this is used by the load_all_component
      if @before && @after
        hidden_events.each_with_index do |event, _index|
          component = if event.respond_to?(:type) && event.type.to_s.start_with?("TIMELINE_EVENT_TYPE_")
            determine_dismissal_timeline_event_component(timeline_event: event, last_event: false)
          else
            determine_timeline_event_component(event: event, last_event: false)
          end
          @timeline_items.push(component) if component
        end
        @timeline_items
      else
        @timeline_items.push(DependabotAlerts::TimelineItems::OpenedComponent.new(alert: alert, last_event: false))

        # Process all events (mixed regular events and dismissal events)
        events.each_with_index do |event, index|
          # if there's more than 20 items we want to show the load all button
          if show_load_all?(index: index)
            @timeline_items.push(DependabotAlerts::TimelineItems::LoadAllComponent.new(load_all_path: load_all_path, hidden_items_count: hidden_items_count))
          end

          # Determine if this is a dismissal timeline event or regular event
          component = if event.respond_to?(:type) && event.type.to_s.start_with?("TIMELINE_EVENT_TYPE_")
            determine_dismissal_timeline_event_component(timeline_event: event, last_event: index == events.length - 1)
          else
            determine_timeline_event_component(event: event, last_event: index == events.length - 1)
          end
          @timeline_items.push(component) if component
        end

        @timeline_items
      end
    end
  end
end
