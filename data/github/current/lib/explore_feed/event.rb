# typed: true
# frozen_string_literal: true

module ExploreFeed
  class Event
    include TextHelper
    include EmailLinkTrackingHelper
    include ExploreFeed::ValidationHelpers
    include GitHub::Memoizer

    FEED_URL = ENV.fetch("EVENTS_FEED_URL", "https://events-feed.github.com")
    REQUIRED_ATTRIBUTES = %w(
      always_show
      display_name
      end_date
      location_full_address
      location_short_name
      parameterized_name
      short_description
      sponsored
      start_date
    ).freeze

    attr_reader(
      :attributes,
      :alternative_date_text,
      :always_show,
      :color,
      :display_name,
      :external_url,
      :image,
      :location_full_address,
      :location_short_name,
      :parameterized_name,
      :short_description,
      :sponsored,
      :topics,
    )

    class << self
      def all
        Collection.new(raw_events.map(&method(:new))).sanitized.sorted
      end

      # Ensures that events are lowercase as Contentful is case sensitive
      def fetch_by_parameterized_name(event_name)
        all
          .find { |event| event.parameterized_name == event_name.downcase }
      end

      private

      def raw_events
        GitHub::JSON::CachedFetchRemoteUrl.fetch(
          url: "#{FEED_URL}/events.json",
          cache_key: "explore:events_feed_collection:latest",
          default_value: {},
          hash_subkey: "items",
        )
      end
    end

    def initialize(attributes)
      @attributes = attributes
      @alternative_date_text = attributes["alternative_date_text"]
      @always_show = attributes["always_show"]
      @color = attributes["color"]
      @content = attributes["content"]
      @display_name = attributes["display_name"]
      @date = attributes["date"]
      @end_date = attributes["end_date"]
      @external_url = attributes["external_url"]
      @image = attributes["image"]
      @location_full_address = attributes["location_full_address"]
      @location_short_name = attributes["location_short_name"]
      @parameterized_name = attributes["parameterized_name"]
      @short_description = attributes["short_description"]
      @sponsored = attributes["sponsored"]
      @start_date = attributes["start_date"]
      @topics = attributes["topics"]
    end

    def url
      external_url.presence ||
        UrlHelpers.event_path(parameterized_name)
    end

    def url_for_mailer(auto_subscribed:)
      email_link_with_tracking(
        url: url,
        email_source: "explore",
        auto_subscribed: auto_subscribed,
      )
    end

    def upcoming_or_current?
      upcoming? || current?
    end

    def past?
      end_date.past?
    end

    def sponsored?
      !!sponsored
    end

    def hosted?
      !sponsored?
    end

    def content
      GitHub::Goomba::MarkdownPipeline.to_html(@content)
    end

    def upcoming?
      start_date.future?
    end

    def current?
      in_progress? || continuous?
    end

    def date
      if @date.present?
        Date.parse(@date)
      end
    end

    memoize def start_date
      if @start_date.present?
        Date.parse(@start_date)
      end
    end

    memoize def end_date
      if @end_date.present?
        Date.parse(@end_date)
      end
    end

    def long_date
      date.to_formatted_s :long
    end

    def long_start_date
      start_date.to_formatted_s :long
    end

    def long_end_date
      end_date.to_formatted_s :long
    end

    def long_date_range
      output = long_start_date

      if end_date != start_date
        output << " - #{long_end_date}"
      end

      output
    end

    def start_month
      start_date.strftime("%b")
    end

    def start_day
      start_date.strftime("%-d")
    end

    def sponsored_date_range
      if start_date == end_date
        long_start_date
      elsif start_date.month == end_date.month && start_date.year == end_date.year
        "#{start_date.strftime("%b %-d")} - #{end_date.day}, #{start_date.year}"
      elsif start_date.year == end_date.year
        "#{start_date.strftime("%B")} - #{end_date.strftime("%B %Y")}"
      else
        "#{start_date.strftime("%b %Y")} - #{end_date.strftime("%b %Y")}"
      end
    end

    private

    def in_progress?
      starting_today? || (start_date.past? && end_date.future?)
    end

    def starting_today?
      start_date.today?
    end

    def continuous?
      alternative_date_text.present? && always_show?
    end

    def always_show?
      always_show
    end

    class Collection
      include Enumerable

      def initialize(events)
        @events = events
      end

      def each(&block)
        events.each(&block)
      end

      def sanitized
        sanitized_events = events.select(&:valid?)

        self.class.new(sanitized_events)
      end

      def sorted
        sorted_events = events
          .sort_by(&:start_date)
          .lazy

        self.class.new(sorted_events)
      end

      def upcoming_or_current
        upcoming_or_current_events = events
          .select(&:upcoming_or_current?)

        self.class.new(upcoming_or_current_events)
      end

      def hosted
        hosted_events = events
          .select(&:hosted?)

        self.class.new(hosted_events)
      end

      def sponsored
        sponsored_events = events
          .select(&:sponsored?)

        self.class.new(sponsored_events)
      end

      def for_topic(topic_name)
        matching_events = events
          .select { |event| event.topics.include? topic_name }

        self.class.new(matching_events)
      end

      def sample
        events.to_a.sample
      end

      private

      attr_accessor :events
    end

  end
end
