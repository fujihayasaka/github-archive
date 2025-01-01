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

    def initialize(alert:, before: nil, after: nil)
      @alert = alert
      @before = before
      @after = after
    end

    memoize def events
      @events ||=
        if show_all_events?
          alert.events.order(:id).preload(:actor).to_a
        else
          first_events + last_events
        end
    end

    memoize def hidden_events
      return [] unless @before && @after

      alert.events.between(after_id: @after, before_id: @before).order(:id).preload(:actor).to_a
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
      alert.events.count
    end

    def show_all_events?
      event_count <= MAX_EVENTS_ON_FIRST_RENDER
    end

    memoize def first_events
      alert.events.order(:id).limit(10).preload(:actor).to_a
    end

    memoize def last_events
      @last_events ||= alert.events.order(id: :desc).limit(10).preload(:actor).to_a.reverse
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
      end
    end

    memoize def timeline_items
      @timeline_items = []
      # if before and after params are present,
      # we need to build the events for the middle of the timeline
      # this is used by the load_all_component
      if @before && @after
        hidden_events.each_with_index do |event, _index|
          event = determine_timeline_event_component(event: event, last_event: false)
          @timeline_items.push(event)
        end
        @timeline_items
      else
        @timeline_items.push(DependabotAlerts::TimelineItems::OpenedComponent.new(alert: alert, last_event: 0 == events.size))

        events.each_with_index do |event, index|
          # if there's more than 20 items we want to show the load all button
          if show_load_all?(index: index)
            @timeline_items.push(DependabotAlerts::TimelineItems::LoadAllComponent.new(load_all_path: load_all_path, hidden_items_count: hidden_items_count))
            event = determine_timeline_event_component(event: event, last_event: index == events.size - 1)
            @timeline_items.push(event)
          else
            # There is less than 20 items, so we can render them all
            event = determine_timeline_event_component(event: event, last_event: index == events.size - 1)
            @timeline_items.push(event)
          end
        end
        @timeline_items
      end
    end
  end
end
