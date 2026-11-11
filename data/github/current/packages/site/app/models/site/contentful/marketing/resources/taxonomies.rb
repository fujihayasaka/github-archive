# typed: true
# frozen_string_literal: true

# Facade class for taxonomy data from Contentful.
# Delegates to Concepts and ConceptSchemes classes for actual implementation.
class Site::Contentful::Marketing::Resources::Taxonomies
  # Fetch all concepts from Contentful with caching
  sig { returns(T::Array[T::Hash[Symbol, T.untyped]]) }
  def self.concepts
    Concepts.all
  end

  # Force a refresh of the concepts from Contentful
  sig { returns(T::Array[T::Hash[Symbol, T.untyped]]) }
  def self.refresh_concepts
    Concepts.refresh
  end

  # Fetch all concept schemes from Contentful with caching
  sig { returns(T::Array[T::Hash[Symbol, T.untyped]]) }
  def self.concept_schemes
    ConceptSchemes.all
  end

  # Find a specific concept scheme by ID
  sig { params(id: String).returns(T::Hash[Symbol, T.untyped]) }
  def self.find_concept_scheme(id)
    ConceptSchemes.fetch_by_id(id)
  end

  # Find a specific concept scheme by ID with localized preferred_label
  sig { params(id: String, locale: String).returns(T::Hash[Symbol, T.untyped]) }
  def self.find_concept_scheme_localized(id, locale)
    scheme = find_concept_scheme(id)
    localized_scheme = scheme.dup
    localized_scheme[:preferred_label] = localize_preferred_label(scheme[:preferred_label], locale)
    localized_scheme
  end

  # Get concepts that belong to a specific concept scheme, with localized preferred_label
  # @param scheme_id [String] The concept scheme ID
  # @param locale [String] The locale to use for the preferred_label (e.g., "en-US", "ja")
  # @return [Array<Hash>] Array of concept hashes with localized preferred_label
  sig { params(scheme_id: String, locale: String).returns(T::Array[T::Hash[Symbol, T.untyped]]) }
  def self.concepts_for_scheme(scheme_id, locale)
    scheme = find_concept_scheme(scheme_id)
    scheme_concept_ids = (scheme[:concepts] || []).map { |c| c[:id] || c["id"] }.compact
    return [] if scheme_concept_ids.empty?

    scheme_concepts = concepts.select { |concept| scheme_concept_ids.include?(concept[:id]) }

    # Select the appropriate locale value for preferred_label
    scheme_concepts.map do |concept|
      localized_concept = concept.dup
      localized_concept[:preferred_label] = localize_preferred_label(concept[:preferred_label], locale)
      localized_concept
    end
  end

  # Select the best locale match for a preferred_label hash
  # Falls back through: exact locale -> base locale -> en-US -> first available value
  sig { params(preferred_label: T.untyped, locale: String).returns(T.untyped) }
  def self.localize_preferred_label(preferred_label, locale)
    return preferred_label unless preferred_label.is_a?(Hash)

    preferred_label[locale] ||
      preferred_label[locale.split("-").first] ||
      preferred_label["en-US"] ||
      preferred_label.values.first
  end

  private_class_method :localize_preferred_label

  # Force a refresh of the concept schemes from Contentful
  sig { returns(T::Array[T::Hash[Symbol, T.untyped]]) }
  def self.refresh_concept_schemes
    ConceptSchemes.refresh
  end

  # Reset cached instances (for testing)
  sig { void }
  def self.reset!
    Concepts.reset!
    ConceptSchemes.reset!
  end
end
