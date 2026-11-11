# typed: true
# frozen_string_literal: true

module ExploreFeed
  class Spotlight
    include ExploreFeed::ValidationHelpers

    REQUIRED_ATTRIBUTES = %w(heading description external_url image).freeze
    SPOTLIGHTS_FEED_URL = "https://spotlights-feed.github.com"

    attr_reader(
      :attributes,
      :color,
      :content_type,
      :dashboard,
      :external_url,
      :github_repo,
      :github_user,
      :heading,
      :image,
      :splash,
      :text_align,
      :topics,
    )

    class << self
      def all
        Collection.new(raw_spotlights.map(&method(:new))).sanitized
      end

      private

      def raw_spotlights
        GitHub::JSON::CachedFetchRemoteUrl.fetch(
          url: "#{SPOTLIGHTS_FEED_URL}/spotlights.json",
          cache_key: "explore:spotlights_feed_collection:latest",
          default_value: {},
          hash_subkey: "items",
        )
      end
    end

    def initialize(attributes)
      @attributes = attributes
      @color = attributes["color"]
      @content_type = attributes["content_type"]
      @dashboard = attributes["dashboard"]
      @description = attributes["description"]
      @end_date = attributes["end_date"]
      @external_url = attributes["external_url"]
      @github_repo = attributes["github_repo"]
      @github_user = attributes["github_user"]
      @heading = attributes["heading"]
      @image = attributes["image"]
      @start_date = attributes["start_date"]
      @text_align = attributes["text_align"]
      @topics = attributes["topics"]
    end

    def description
      GitHub::Goomba::MarkdownPipeline.to_html(@description)
    end

    def start_date
      if @start_date.present?
        Date.parse(@start_date)
      end
    end

    def end_date
      if @end_date.present?
        Date.parse(@end_date)
      end
    end

    def dashboard?
      !!dashboard
    end

    def repository?
      github_repo.present? && github_user.present?
    end

    def current?
      (starting_today? || already_started?) && (ending_today? || ending_in_the_future?)
    end

    private

    def starting_today?
      if start_date.present?
        start_date.to_s == Date.today.to_s
      end
    end

    def already_started?
      if start_date.present?
        start_date.past?
      else
        true
      end
    end

    def ending_today?
      if end_date.present?
        end_date.to_s == Date.today.to_s
      end
    end

    def ending_in_the_future?
      if end_date.present?
        end_date.future?
      else
        true
      end
    end

    class Collection
      include Enumerable

      def initialize(spotlights)
        @spotlights = spotlights
      end

      def each(&block)
        spotlights.each(&block)
      end

      def sanitized
        sanitized_spotlights = spotlights.select(&:valid?)

        self.class.new(sanitized_spotlights)
      end

      def sorted
        sorted_spotlights = spotlights
          .sort_by(&:start_date)
          .lazy

        self.class.new(sorted_spotlights)
      end

      def current
        current_spotlights = spotlights.select(&:current?)

        self.class.new(current_spotlights)
      end

      def dashboard
        dashboard_spotlights = spotlights.select(&:dashboard?)

        self.class.new(dashboard_spotlights)
      end

      def for_topic(topic_name)
        topic_spotlights = spotlights.select { |spotlight| spotlight.topics.include?(topic_name) }

        self.class.new(topic_spotlights)
      end

      private

      attr_accessor :spotlights
    end
  end
end
