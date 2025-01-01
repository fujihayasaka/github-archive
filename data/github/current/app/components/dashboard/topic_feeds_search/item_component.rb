# typed: true
# frozen_string_literal: true

module Dashboard

  module TopicFeedsSearch

    class ItemComponent < ApplicationComponent
      def initialize(topic:, query: "", **system_arguments)
        @topic = topic
        @query = query
        @system_arguments = system_arguments
      end

      def follower_count_text
        helpers.topic_followers_formatted(topic)
      end

      private

      attr_reader :topic, :system_arguments, :query

      def render?
        topic.present?
      end

      def link_hydro_data
        helpers.feed_clicks_hydro_attrs(click_target: "topic_feed_search_result_link", metadata: {
          clicked_resource_type: Conduit::AnalyticsHelper::ResourceType::TOPIC,
          clicked_resource_id: topic.id
        })
      end

      def star_hydro_data
        helpers.feed_clicks_hydro_attrs(click_target: "topic_feed_star_button", metadata: {
          clicked_resource_type: Conduit::AnalyticsHelper::ResourceType::TOPIC,
          clicked_resource_id: topic.id
        })
      end
    end
  end
end
