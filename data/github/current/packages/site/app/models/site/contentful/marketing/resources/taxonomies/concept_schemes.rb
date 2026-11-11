# typed: strict
# frozen_string_literal: true

class Site::Contentful::Marketing::Resources::Taxonomies::ConceptSchemes < Site::Contentful::Marketing::Resources::Taxonomies::BaseTaxonomy
  class << self

    sig { returns(T::Array[T::Hash[Symbol, T.untyped]]) }
    def all
      instance.items
    end

    sig { params(id: String).returns(T::Hash[Symbol, T.untyped]) }
    def fetch_by_id(id)
      all.find { |scheme| scheme[:id] == id } || { id: id, concepts: [] }
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

    sig { returns(Site::Contentful::Marketing::Resources::Taxonomies::ConceptSchemes) }
    def instance
      @instance ||= T.let(new, T.nilable(Site::Contentful::Marketing::Resources::Taxonomies::ConceptSchemes))
    end
  end

  sig { override.returns(Site::Contentful::Page::CacheKey) }
  def cache_key
    Site::Contentful::Page::CacheKey.new(
      base: "site.contentful.marketing.resources.taxonomies",
      path: "concept_schemes",
      version: 1,
    )
  end

  sig { override.returns(T::Array[T::Hash[Symbol, T.untyped]]) }
  def fetch_items
    response = fetch_from_api(build_uri)

    return [] if response.blank?

    extract_concept_schemes(response)
  rescue StandardError => err
    Failbot.report(err, "Error fetching concept schemes from Contentful")
    GitHub.dogstats.increment(
      "site.contentful.taxonomies.concept_schemes.fetch_failures",
      tags: ["error:#{err.class}"]
    )
    raise if Rails.env.development?
    []
  end

  private

  sig { returns(URI::Generic) }
  def build_uri
    URI.parse(
      "#{BASE_URL}/spaces/#{space_id}/environments/#{environment}/taxonomy/concept-schemes?limit=100"
    )
  end

  sig { params(response: T::Hash[String, T.untyped]).returns(T::Array[T::Hash[Symbol, T.untyped]]) }
  def extract_concept_schemes(response)
    items = response.dig("items") || []

    items.map do |scheme|
      pref_label = scheme.dig("prefLabel")

      preferred_label =
        if pref_label.is_a?(Hash)
          pref_label.transform_keys(&:to_s).reject { |_locale, value| value.blank? }.presence
        elsif pref_label.present?
          { "en-US" => pref_label.to_s }
        end

      {
        id: scheme.dig("sys", "id"),
        uri: scheme.dig("uri"),
        # Store all locale values - will be selected by locale at request time
        preferred_label: preferred_label,
        definition: extract_localized_field(scheme, "definition"),
        top_concepts: extract_linked_concepts(scheme, "topConcepts"),
        concepts: extract_linked_concepts(scheme, "concepts"),
        total_concepts: scheme.dig("totalConcepts")
      }.compact
    end
  end

  sig { params(scheme: T::Hash[String, T.untyped], field_name: String).returns(T::Array[T::Hash[Symbol, T.untyped]]) }
  def extract_linked_concepts(scheme, field_name)
    concepts = scheme.dig(field_name) || []

    concepts.map do |concept|
      {
        id: concept.dig("sys", "id"),
        type: concept.dig("sys", "linkType")
      }.compact
    end
  end
end
