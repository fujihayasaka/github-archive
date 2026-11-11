# typed: true
# frozen_string_literal: true

module DependabotAlerts
  module TimelineItems
    class DismissalReviewedComponent < ApplicationComponent
      include ViewComponent::InlineTemplate

      erb_template <<~'ERB'
        <div class="tmp-ml-5">
          <%= render(Primer::Beta::TimelineItem.new(pb: padding, test_selector: "alert-timeline-event-dismissal-reviewed")) do |component| %>
            <% component.with_badge(color: badge_color, icon: badge_icon) %>
            <% component.with_body do %>
              <%= render DependabotAlerts::TimelineItems::ActorComponent.new(actor: actor) %>
              <%= dismissal_resolution_msg %>
              <%= render Primer::Beta::RelativeTime.new(datetime: timestamp_time, tense: :past) %>
            <% end %>
          <% end %>
          <% if reviewer_comment.present? %>
            <div class="TimelineItem tmp-pl-5 pt-0 f6 d-block dependabot-alert-dismissal-comment" <%= test_selector("alert-timeline-event-dismissal-reviewed-comment") %>>
              <%= render Primer::Beta::Octicon.new(icon: "note") %>
              <%= reviewer_comment %>
            </div>
          <% end %>
        </div>
      ERB

      attr_reader :timeline_event, :actor, :last_event

      def initialize(timeline_event:, actor:, last_event:)
        @timeline_event = timeline_event
        @actor = actor
        @last_event = last_event
      end

      private

      def padding
        last_event ? 0 : 3
      end

      def dismissal_resolution_msg
        status = timeline_event.compute_status
        if status == "approved"
          return "approved dismissal"
        end

        if status == "rejected"
          return "denied dismissal"
        end

        "reviewed dismissal"
      end

      def badge_color
        case timeline_event.compute_status
        when "approved"
          :success
        when "rejected"
          :danger
        else
          :secondary
        end
      end

      def badge_icon
        case timeline_event.compute_status
        when "approved"
          :"check"
        when "rejected"
          :"x"
        else
          :"comment"
        end
      end

      def reviewer_comment
        timeline_event.reviewer_comment
      end

      def timestamp_time
        return Time.now unless timeline_event.timestamp

        Time.at(timeline_event.timestamp.seconds, timeline_event.timestamp.nanos, :nsec)
      end
    end
  end
end
