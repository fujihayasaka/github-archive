# typed: true
# frozen_string_literal: true

module DependabotAlerts
  module TimelineItems
    class DismissalRequestedComponent < ApplicationComponent
      include ViewComponent::InlineTemplate

      erb_template <<~'ERB'
        <div class="ml-5">
          <%= render(Primer::Beta::TimelineItem.new(pb: padding, test_selector: "alert-timeline-event-dismissal-requested")) do |component| %>
            <% component.with_badge(color: :attention, icon: "comment") %>
            <% component.with_body do %>
              <%= render DependabotAlerts::TimelineItems::ActorComponent.new(actor: actor) %>
              requested to dismiss this as <strong><%= resolution %></strong>
              <%= render Primer::Beta::RelativeTime.new(datetime: timestamp_time, tense: :past) %>
              <% if show_dismissal_actions %>
                <span class="float-right">
                  <%= render DependabotAlerts::DismissalReviewDialogComponent.new(
                    timeline_event: timeline_event,
                    dismissal_request_review_path: dismissal_request_review_path,
                    alert: alert
                  ) %>
                </span>
              <% end %>
            <% end %>
          <% end %>
          <% if resolution_note.present? %>
            <div class="TimelineItem pl-5 pt-0 f6 d-block dependabot-alert-dismissal-comment" <%= test_selector("alert-timeline-event-dismissal-comment") %>>
              <%= render Primer::Beta::Octicon.new(icon: "note") %>
              <%= resolution_note %>
            </div>
          <% end %>
        </div>
      ERB

      attr_reader :timeline_event, :actor, :last_event, :dismissal_request_review_path, :alert

      def initialize(timeline_event:, actor:, last_event:, dismissal_request_review_path:, alert:)
        @timeline_event = timeline_event
        @actor = actor
        @last_event = last_event
        @dismissal_request_review_path = dismissal_request_review_path
        @alert = alert
      end

      private

      def padding
        last_event ? 0 : 3
      end

      def resolution
        timeline_event.resolution&.humanize || "unknown reason"
      end

      def resolution_note
        timeline_event.resolution_note
      end

      def timestamp_time
        return Time.now unless timeline_event.timestamp

        Time.at(timeline_event.timestamp.seconds, timeline_event.timestamp.nanos, :nsec)
      end

      def show_dismissal_actions
        timeline_event.show_dismissal_actions
      end
    end
  end
end
