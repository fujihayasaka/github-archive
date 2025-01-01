# typed: true
# frozen_string_literal: true

module Dashboard
  module Sidebar
    class ChangelogComponent < ApplicationComponent
      CHANGELOG_URL = "https://github.blog/changelog"
      FEED_URL = "https://github.blog/wp-json/wp/v2/changelogs"
      MAX_ITEMS = 4

      def render?
        !GitHub.enterprise? && items.any?
      end

      memoize def items
        raw_events.take(MAX_ITEMS).map do |item|
          {
            title: CGI::unescape_html(item["title"]["rendered"]),
            url: item["link"],
            date: item["date_gmt"].to_datetime,
          }
        end
      end

      private

      def raw_events
        GitHub::JSON::CachedFetchRemoteUrl.fetch(
          url: FEED_URL,
          cache_key: "dashboard:changelog_items:latest",
          default_value: [],
        )
      end
    end
  end
end
