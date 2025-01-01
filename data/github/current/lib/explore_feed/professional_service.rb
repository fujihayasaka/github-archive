# typed: true
# frozen_string_literal: true

# rubocop:disable GitHub/FindByDef

module ExploreFeed
  class ProfessionalService
    include ExploreFeed::ValidationHelpers

    PROFESSIONAL_SERVICES_FEED_URL =
      ENV.fetch("PROFESSIONAL_SERVICES_FEED_URL", "https://ps-resources.github.io/es-offerings-site-feed")
    REQUIRED_ATTRIBUTES = %w(lead parameterized_name title).freeze

    attr_reader(
      :attributes,
      :lead,
      :parameterized_name,
      :title,
    )

    class << self
      def all
        Collection.new(raw_professional_services.map(&method(:new))).sanitized
      end

      def find_by_parameterized_name(parameterized_name)
        all.find { |story| story.parameterized_name == parameterized_name }
      end

      private

      def raw_professional_services
        GitHub::JSON::CachedFetchRemoteUrl.fetch(
          url: "#{PROFESSIONAL_SERVICES_FEED_URL}/feed.json",
          cache_key: "site:professional_services_collection:latest",
          default_value: {},
          hash_subkey: "items",
        )
      end
    end

    def initialize(attributes)
      @attributes = attributes
      @content = attributes["content"]
      @lead = attributes["lead"]
      @parameterized_name = attributes["parameterized_name"]
      @title = attributes["title"]
    end

    def ==(other_proffesional_service)
      parameterized_name == other_proffesional_service.parameterized_name
    end

    def to_param
      parameterized_name
    end

    def content
      GitHub::Goomba::MarkdownPipeline.to_html(@content)
    end

    def url
      "/services/#{parameterized_name}" if parameterized_name
    end

    class Collection
      include Enumerable

      def initialize(services)
        @services = services
      end

      def each(&block)
        @services.each(&block)
      end

      def sanitized
        sanitized_services = services.select(&:valid?)

        self.class.new(sanitized_services)
      end

      private

      attr_accessor :services
    end
  end
end
