# typed: true
# frozen_string_literal: true

module DependabotAlerts
  module TimelineItems
    class DismissalCancelledComponent < ApplicationComponent
      include ViewComponent::InlineTemplate

      erb_template <<~'ERB'
        <div class="ml-5">
          <%= render(Primer::Beta::TimelineItem.new(pb: padding, test_selector: "alert-timeline-event-dismissal-cancelled")) do |component| %>
            <% component.with_badge(color: badge_color, icon: badge_icon) %>
            <% component.with_body do %>
              <%= render DependabotAlerts::TimelineItems::ActorComponent.new(actor: actor) %>
              cancelled their dismissal request
              <%= render Primer::Beta::RelativeTime.new(datetime: timestamp_time, tense: :past) %>
            <% end %>
          <% end %>
        </div>
      ERB

      attr_reader :timeline_event, :actor, :last_event

      def initialize(timeline_event:, actor:, last_event:)
        @timeline_event = timeline_event
        @actor = actor
        @last_event = last_event
      end

      def badge_color
        :subtle
      end

      def badge_icon
        "x"
      end

      def padding
        last_event ? 0 : 3
      end

      def timestamp_time
        if timeline_event.timestamp.respond_to?(:seconds)
          Time.at(timeline_event.timestamp.seconds, timeline_event.timestamp.nanos / 1000.0, :microsecond)
        else
          timeline_event.timestamp
        end
      end
    end
  end
end
