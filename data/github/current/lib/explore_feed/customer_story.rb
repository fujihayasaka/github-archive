# typed: true
# frozen_string_literal: true
# rubocop:disable GitHub/FindByDef

module ExploreFeed
  class CustomerStory
    include ExploreFeed::ValidationHelpers

    CUSTOMER_STORIES_FEED_URL =
      ENV.fetch("CUSTOMER_STORIES_FEED_URL", "https://customer-stories-feed.github.com")
    MORE_STORIES_LIMIT = 4
    NUMBER_OF_OTHER_FEATURED_STORIES = 3
    REQUIRED_ATTRIBUTES = %w(lead parameterized_name title).freeze

    attr_reader(
      :attributes,
      :categories,
      :exclude_from_index,
      :hero_image,
      :industry_filters,
      :lead,
      :logo_image,
      :ordering,
      :parameterized_name,
      :regions,
      :title,
      :video,
      :audio,
    )

    delegate :open_source, :site_index_feature, to: :ordering, prefix: true

    class << self
      def all
        Collection.new(raw_customer_stories.map(&method(:new))).sanitized
      end

      def find_by_parameterized_name(parameterized_name)
        all.find { |story| story.parameterized_name == parameterized_name }
      end

      def featured
        stories = all.select(&:featured?)
        main_featured_story = stories.find(&:main_featured?)
        other_featured_stories = stories - [main_featured_story]

        [
          main_featured_story,
          other_featured_stories.sample(NUMBER_OF_OTHER_FEATURED_STORIES),
        ].flatten.compact
      end

      def open_source
        all
          .select(&:open_source?)
          .sort_by(&:ordering_open_source)
      end

      private

      def raw_customer_stories
        GitHub::JSON::CachedFetchRemoteUrl.fetch(
          url: "#{CUSTOMER_STORIES_FEED_URL}/customer-stories.json",
          cache_key: "site:customer_stories_feed_collection:latest",
          default_value: {},
          hash_subkey: "items",
        )
      end
    end

    def initialize(attributes)
      @attributes = attributes
      @categories = attributes["categories"]
      @content = attributes["content"]
      @exclude_from_index = attributes["exclude_from_index"]
      @facts = attributes["facts"]
      @featured = attributes["featured"]
      @hero_image = attributes["hero_image"]
      @industry_filters = attributes["industry_filters"]
      @integration = attributes["integration"]
      @lead = attributes["lead"]
      @logo_image = attributes["logo_image"]
      @main_featured = attributes["main_featured"]
      @open_source = attributes["open_source"]
      @ordering = Ordering.new(attributes["ordering"])
      @parameterized_name = attributes["parameterized_name"]
      @regions = attributes["regions"]
      @site_index_feature_type = attributes["site_index_feature_type"]
      @title = attributes["title"]
      @video = attributes["video"]
      @audio = attributes["audio"]
    end

    def more_customer_stories
      self.class.all.without(self).sample(MORE_STORIES_LIMIT)
    end

    def ==(other_customer_story)
      parameterized_name == other_customer_story.parameterized_name
    end

    def to_param
      parameterized_name
    end

    def enterprise?
      categories.include?("Enterprise")
    end

    def developers?
      categories.include?("Developers")
    end

    def team?
      categories.include?("Team")
    end

    def site_index_featured?
      @site_index_feature_type.present?
    end

    def customer_type?
      @site_index_feature_type == "customers"
    end

    def developer_type?
      @site_index_feature_type == "developers"
    end

    def featured?
      !!@featured
    end

    def main_featured?
      !!@main_featured
    end

    def open_source?
      !!@open_source
    end

    def content
      GitHub::Goomba::MarkdownPipeline.to_html(@content)
    end

    def url
      if primary_category == "Videos"
        video["url"]
      else
        UrlHelpers.customer_story_path(self)
      end
    end

    def integration
      return unless @integration.present?

      @_integration ||= Integration.new(@integration)
    end

    def facts
      return [] unless @facts.present?

      @facts.map { |key, value| Fact.new(key, value) }
    end

    def industry_value
      facts.find(&:industry?)&.value
    end

    def primary_category
      if categories.present?
        categories.first
      else
        ""
      end
    end

    class Ordering
      attr_reader :open_source, :site_index_feature

      def initialize(attributes)
        attributes ||= {}

        @open_source = attributes["open_source"]&.to_i
        @site_index_feature = attributes["site_index_feature"]&.to_i
      end
    end

    class Fact
      include ActionView::Helpers::SanitizeHelper

      FACT_WORD_MAPPING = {
        "fy" => "FY",
        "it" => "IT",
      }

      def initialize(name, value)
        @name = name
        @value = value
      end

      def name
        words = @name.humanize.split(" ").map do |word|
          FACT_WORD_MAPPING[word] || word
        end

        words.join(" ")
      end

      def value
        sanitize(@value)
      end

      def industry?
        value.present? && @name == "industry"
      end
    end

    class Integration
      attr_reader :heading, :title

      def initialize(attributes)
        @body = attributes["body"]
        @heading = attributes["heading"]
        @items = attributes["items"]
        @title = attributes["title"]
      end

      def body
        GitHub::Goomba::MarkdownPipeline.to_html(@body)
      end

      def items
        return unless @items.present?

        @_items ||= @items.map { |item| Item.new(item) }
      end

      class Item
        attr_reader :heading, :icon

        def initialize(attributes)
          @body = attributes["body"]
          @heading = attributes["heading"]
          @icon = attributes["icon"]
        end

        def body
          GitHub::Goomba::MarkdownPipeline.to_html(@body)
        end
      end
    end

    class Collection
      include Enumerable

      def initialize(stories)
        @stories = stories
      end

      def each(&block)
        @stories.each(&block)
      end

      def sanitized
        sanitized_stories = stories.select(&:valid?)

        self.class.new(sanitized_stories)
      end

      def included_in_index
        self.class.new(stories.reject(&:exclude_from_index))
      end

      def filter_by_type(type_filter)
        filtered_stories = if type_filter.nil? || type_filter == "all"
          stories.flatten
        elsif type_filter == "enterprise"
          stories.flatten.select(&:enterprise?)
        elsif type_filter == "team"
          stories.flatten.select(&:team?)
        elsif type_filter == "developers"
          stories.flatten.select(&:developers?)
        else
          []
        end

        self.class.new(filtered_stories)
      end

      def filter_by_region(region_filter)
        filtered_stories = if region_filter.nil? || region_filter == "all"
          stories.flatten
        else
          stories.flatten.select do |story|
            story.regions.presence&.include?(region_filter)
          end
        end

        self.class.new(filtered_stories)
      end

      def filter_by_industry(industry_filter)
        filtered_stories = if industry_filter.nil? || industry_filter == "all"
          stories.flatten
        else
          stories.flatten.select do |story|
            story.industry_filters.presence&.include?(industry_filter)
          end
        end

        self.class.new(filtered_stories)
      end

      private

      attr_accessor :stories
    end
  end
end
