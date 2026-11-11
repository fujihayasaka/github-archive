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
        raw_events.take(MAX_ITEMS).filter_map do |item|
          raw_title = item.dig("title", "rendered")
          next if raw_title.nil?

          if !raw_title.valid_encoding?
            raw_title = raw_title.encode("UTF-8", invalid: :replace, undef: :replace, replace: "")
            GitHub.logger.warn("changelog: invalid or undefined characters removed from title")
            GitHub.dogstats.increment(
              "dashboard.changelog.invalid_title_characters",
              tags: ["component:Dashboard::Sidebar::ChangelogComponent"],
              message: "Invalid characters were found and removed from blog entry title: #{raw_title}.",
            )
          end

          {
            title: CGI::unescape_html(raw_title),
            url: item["link"],
            date: item["date_gmt"]&.to_datetime,
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

      def changelog_item_hydro_attributes
        helpers.dashboard_hydro_click_tracking_attributes(
          event_context: :LATEST_CHANGES,
          target: :CHANGELOG
        )
      end
    end
  end
end
