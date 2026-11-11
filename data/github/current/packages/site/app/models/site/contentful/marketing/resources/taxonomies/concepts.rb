# typed: strict
# frozen_string_literal: true

class Site::Contentful::Marketing::Resources::Taxonomies::Concepts < Site::Contentful::Marketing::Resources::Taxonomies::BaseTaxonomy
  class << self
    sig { returns(T::Array[T::Hash[Symbol, T.untyped]]) }
    def all
      instance.items
    end

    sig { returns(T::Array[T::Hash[Symbol, T.untyped]]) }
    def refresh
      instance.revalidate
    end

    sig { void }
    def reset!
      @instance = nil
    end

    private

    sig { returns(Site::Contentful::Marketing::Resources::Taxonomies::Concepts) }
    def instance
      @instance ||= T.let(new, T.nilable(Site::Contentful::Marketing::Resources::Taxonomies::Concepts))
    end
  end

  sig { override.returns(Site::Contentful::Page::CacheKey) }
  def cache_key
    Site::Contentful::Page::CacheKey.new(
      base: "site.contentful.marketing.resources.taxonomies",
      path: "concepts",
      version: 1,
    )
  end

  sig { override.returns(T::Array[T::Hash[Symbol, T.untyped]]) }
  def fetch_items
    response = fetch_from_api(build_uri)

    return [] if response.blank?

    extract_concepts(response)
  rescue StandardError => err
    Failbot.report(err, "Error fetching concepts from Contentful")
    GitHub.dogstats.increment(
      "site.contentful.taxonomies.concepts.fetch_failures",
      tags: ["error:#{err.class}"]
    )
    raise if Rails.env.development?
    []
  end

  private

  sig { returns(URI::Generic) }
  def build_uri
    URI.parse(
      "#{BASE_URL}/spaces/#{space_id}/environments/#{environment}/taxonomy/concepts?limit=100"
    )
  end

  sig { params(response: T::Hash[String, T.untyped]).returns(T::Array[T::Hash[Symbol, T.untyped]]) }
  def extract_concepts(response)
    items = response.dig("items") || []

    items.map do |concept|
      pref_label = concept.dig("prefLabel")

      preferred_label =
        if pref_label.is_a?(Hash)
          pref_label.transform_keys(&:to_s).reject { |_locale, value| value.blank? }.presence
        elsif pref_label.present?
          { "en-US" => pref_label.to_s }
        end

      {
        id: concept.dig("sys", "id"),
        uri: concept.dig("uri"),
        # Store all locale values - will be selected by locale at request time
        preferred_label: preferred_label,
        definition: extract_localized_field(concept, "definition")
      }.compact
    end
  end
end
